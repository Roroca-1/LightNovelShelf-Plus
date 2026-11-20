import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import '../../core/network/request_scheduler.dart';
import '../api/api_client.dart';
import '../api/models.dart';
import '../providers.dart';
import 'shelf_draft.dart';

/// 书架错误文案，草稿代数抛出的 [ArgumentError] 消息直接展示给用户。
String describeShelfError(Object error, {String fallback = '书架暂时不可用。'}) {
  if (error is ArgumentError) return error.message?.toString() ?? fallback;
  return describeApiError(
    error,
    fallback: fallback,
    auth: '登录状态已过期，请重新登录后继续。',
    network: '网络连接不可用，请检查后重试。',
    normalize: true,
  );
}

/// 书架仓库：加载、保存（串行队列 + 代际号）与单本增删。
class ShelfController extends AsyncNotifier<ShelfSnapshot?> {
  ApiClient get _api => ref.read(apiClientProvider);

  int _mutationGeneration = 0;
  Future<void> _saveQueue = Future<void>.value();

  @override
  Future<ShelfSnapshot?> build() async {
    // 只看登录与否，token 刷新途中的 refreshing 快照不该把书架拆掉重拉。
    final authenticated = ref.watch(
      authSnapshotProvider.select((snapshot) => snapshot.isAuthenticated),
    );
    if (!authenticated) return null;
    final cached = await ref.read(bookMetadataCacheProvider).readShelf();
    if (cached != null) {
      unawaited(_refreshInBackground());
      return cached;
    }
    return _load();
  }

  Future<void> _refreshInBackground() async {
    try {
      final snapshot = await _load();
      if (!ref.mounted) return;
      state = AsyncValue<ShelfSnapshot?>.data(snapshot);
    } catch (_) {
      // Keep the cached shelf visible when background refresh fails.
    }
  }

  Future<ShelfSnapshot> _hydrate(
    List<ShelfItem> items, {
    required int generation,
  }) async {
    final bookIds = items
        .where((item) => item.isBook)
        .map((item) => item.bookId!)
        .toList();
    final books = await ref
        .read(bookMetadataCacheProvider)
        .resolve(bookIds, _api.getBooksByIdsBatched);
    final missingAuthors = books
        .where(
          (book) =>
              book.type == BookType.novel &&
              (book.authorName == null || book.authorName!.trim().isEmpty),
        )
        .toList();
    if (missingAuthors.isNotEmpty) {
      // 补全缺失作者走低优先级后台受限并发，不阻塞书架展示也不抢占交互限流配额。
      unawaited(_backfillMissingAuthors(missingAuthors, generation));
    }
    return ShelfSnapshot(items: sortShelfItems(items), books: books);
  }

  Future<void> _backfillMissingAuthors(
    List<BookListItem> missingAuthors,
    int generation,
  ) async {
    const int maxConcurrency = 2;
    final updated = <int, BookListItem>{};
    var cursor = 0;

    Future<void> worker() async {
      while (cursor < missingAuthors.length) {
        if (!ref.mounted || generation != _mutationGeneration) return;
        final book = missingAuthors[cursor++];
        try {
          final detail = await _api.getBookInfo(
            book.id,
            priority: RequestPriority.preload,
          );
          final author = detail.authorName ?? detail.classification.author;
          if (author != null && author.trim().isNotEmpty) {
            updated[book.id] = book.copyWith(authorName: author.trim());
          }
        } catch (_) {
          // 单个书目补全失败忽略，不影响书架其余内容。
        }
      }
    }

    await Future.wait(
      List<Future<void>>.generate(
        math.min(maxConcurrency, missingAuthors.length),
        (_) => worker(),
      ),
    );
    if (updated.isEmpty || !ref.mounted) return;
    await ref.read(bookMetadataCacheProvider).putAll(updated.values);
    if (!ref.mounted || generation != _mutationGeneration) return;
    final current = state.value;
    if (current == null) return;
    final refreshed = ShelfSnapshot(
      items: current.items,
      books: <BookListItem>[
        for (final book in current.books) updated[book.id] ?? book,
      ],
    );
    state = AsyncValue<ShelfSnapshot?>.data(refreshed);
    await ref.read(bookMetadataCacheProvider).writeShelf(refreshed);
  }

  Future<ShelfSnapshot> _load() async {
    await _saveQueue;
    final generation = _mutationGeneration;
    final shelf = await _api.getBookShelf();
    final snapshot = await _hydrate(shelf.items, generation: generation);
    if (generation != _mutationGeneration) {
      return state.value ?? snapshot;
    }
    await ref.read(bookMetadataCacheProvider).writeShelf(snapshot);
    return snapshot;
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(() async {
      if (!ref.read(authSnapshotProvider).isAuthenticated) return null;
      return _load();
    });
  }

  Future<T> _enqueueMutation<T>(Future<T> Function() operation) {
    final next = _saveQueue.then(
      (_) => operation(),
      onError: (_) => operation(),
    );
    _saveQueue = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<ShelfSnapshot> _saveUnlocked(ShelfDraft draft, int generation) async {
    final normalized = ShelfDraft(items: normalizeShelfIndexes(draft.items));
    await _api.saveBookShelf(UserShelf(items: normalized.items));
    final knownBooks = <int, BookListItem>{
      for (final book in state.value?.books ?? const <BookListItem>[])
        book.id: book,
    };
    final missingIds = normalized.items
        .where((item) => item.isBook && !knownBooks.containsKey(item.bookId))
        .map((item) => item.bookId!)
        .toList();
    if (missingIds.isNotEmpty) {
      for (final book in await ref
          .read(bookMetadataCacheProvider)
          .resolve(missingIds, _api.getBooksByIdsBatched)) {
        knownBooks[book.id] = book;
      }
    }
    final nextIds = normalized.items
        .where((item) => item.isBook)
        .map((item) => item.bookId!)
        .toSet();
    final snapshot = ShelfSnapshot(
      items: normalized.items,
      books: knownBooks.values
          .where((book) => nextIds.contains(book.id))
          .toList(),
    );
    if (ref.mounted && generation == _mutationGeneration) {
      state = AsyncValue<ShelfSnapshot?>.data(snapshot);
    }
    await ref.read(bookMetadataCacheProvider).writeShelf(snapshot);
    return snapshot;
  }

  Future<ShelfSnapshot> save(ShelfDraft draft) {
    final generation = ++_mutationGeneration;
    return _enqueueMutation(() => _saveUnlocked(draft, generation));
  }

  /// 没有缓存快照时回源查询。
  Future<bool> contains(
    int bookId, {
    ShelfItemType type = ShelfItemType.novel,
  }) async {
    final snapshot = state.value;
    if (snapshot != null) {
      return shelfContainsBook(snapshot.items, bookId, type: type);
    }
    final shelf = await _api.getBookShelf();
    return shelfContainsBook(shelf.items, bookId, type: type);
  }

  /// 加入/移出书架，返回操作后是否在书架中。
  Future<bool> toggleBook(
    int bookId, {
    ShelfItemType type = ShelfItemType.novel,
  }) {
    if (bookId <= 0) {
      return Future<bool>.error(ArgumentError('无效的书籍 ID。'));
    }
    final generation = ++_mutationGeneration;
    return _enqueueMutation(() async {
      final shelf = await _api.getBookShelf();
      final isInShelf = shelfContainsBook(shelf.items, bookId, type: type);
      final items = isInShelf
          ? shelf.items
                .where(
                  (item) =>
                      !item.isBook ||
                      item.bookId != bookId ||
                      item.type != type,
                )
                .toList()
          : <ShelfItem>[
              ShelfItem.book(
                type: type,
                id: bookId,
                index: -1,
                parents: const <String>[],
                updatedAt: DateTime.now().toUtc().toIso8601String(),
              ),
              ...shelf.items,
            ];
      await _saveUnlocked(ShelfDraft(items: items), generation);
      return !isInShelf;
    });
  }

  /// 一次把多本书加入根目录；已在书架中的条目保持原位置且不会重复。
  Future<int> addBooks(Iterable<int> bookIds) {
    final ids = bookIds.where((id) => id > 0).toSet();
    if (ids.isEmpty) return Future<int>.value(0);
    final generation = ++_mutationGeneration;
    return _enqueueMutation(() async {
      final shelf = await _api.getBookShelf();
      final existing = shelf.items
          .where((item) => item.isBook)
          .map((item) => item.bookId!)
          .toSet();
      final missing = ids.difference(existing);
      if (missing.isEmpty) return 0;
      final now = DateTime.now().toUtc().toIso8601String();
      await _saveUnlocked(
        ShelfDraft(
          items: <ShelfItem>[
            for (final id in missing)
              ShelfItem.book(
                id: id,
                index: -1,
                parents: const <String>[],
                updatedAt: now,
              ),
            ...shelf.items,
          ],
        ),
        generation,
      );
      return missing.length;
    });
  }

  /// 一次从书架移出多本书，文件夹和其余条目的位置保持不变。
  Future<int> removeBooks(Iterable<int> bookIds) {
    final ids = bookIds.where((id) => id > 0).toSet();
    if (ids.isEmpty) return Future<int>.value(0);
    final generation = ++_mutationGeneration;
    return _enqueueMutation(() async {
      final shelf = await _api.getBookShelf();
      final removed = shelf.items
          .where((item) => item.isBook && ids.contains(item.bookId))
          .length;
      if (removed == 0) return 0;
      await _saveUnlocked(
        ShelfDraft(
          items: shelf.items
              .where((item) => !item.isBook || !ids.contains(item.bookId))
              .toList(),
        ),
        generation,
      );
      return removed;
    });
  }
}

final AsyncNotifierProvider<ShelfController, ShelfSnapshot?> shelfProvider =
    AsyncNotifierProvider<ShelfController, ShelfSnapshot?>(ShelfController.new);
