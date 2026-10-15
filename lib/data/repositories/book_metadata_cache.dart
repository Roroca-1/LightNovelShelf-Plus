import 'dart:convert';

import '../../core/platform/stores.dart';
import '../api/models.dart';
import 'shelf_draft.dart';

const String bookMetadataCacheKey = 'lightnovel.cache.book-metadata.v2';
const String homeContentCachePrefix = 'lightnovel.cache.home.v1.';
const String shelfSnapshotCacheKey = 'lightnovel.cache.shelf.v2';
const String historyIndexCacheKey = 'lightnovel.cache.history-preview.v2';
const String profileCacheKey = 'lightnovel.cache.profile.v1';

class BookMetadataCache {
  BookMetadataCache(this._store);
  final KeyValueStore _store;

  Future<List<BookListItem>> resolve(
    List<int> ids,
    Future<List<BookListItem>> Function(List<int>) loader,
  ) async {
    final cached = await _read();
    final missing = ids.where((id) => !cached.containsKey(id)).toList();
    if (missing.isNotEmpty) {
      final fetched = await loader(missing);
      for (final book in fetched) {
        cached[book.id] = book;
      }
      await _write(cached);
    }
    return <BookListItem>[
      for (final id in ids) ?cached[id],
    ];
  }

  Future<Map<int, BookListItem>> _read() async {
    try {
      final raw = await _store.read(bookMetadataCacheKey);
      if (raw == null) return <int, BookListItem>{};
      final record = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(record['savedAt'] as String? ?? '');
      if (savedAt == null || DateTime.now().difference(savedAt).inDays >= 7) {
        return <int, BookListItem>{};
      }
      return <int, BookListItem>{
        for (final value in record['items'] as List<dynamic>)
          if (value is Map<String, dynamic>)
            BookListItem.decode(value).id: BookListItem.decode(value),
      };
    } catch (_) {
      return <int, BookListItem>{};
    }
  }

  Future<void> _write(Map<int, BookListItem> books) => _store.write(
    bookMetadataCacheKey,
    jsonEncode(<String, Object?>{
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'items': books.values.take(1000).map((book) => book.encode()).toList(),
    }),
  );

  Future<void> putAll(Iterable<BookListItem> books) async {
    final cached = await _read();
    for (final book in books) {
      cached[book.id] = book;
    }
    await _write(cached);
  }

  Future<void> clear() => _store.delete(bookMetadataCacheKey);

  Future<List<BookListItem>?> readList(String name, Duration maxAge) async {
    try {
      final raw = await _store.read('$homeContentCachePrefix$name');
      if (raw == null) return null;
      final record = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.parse(record['savedAt'] as String);
      if (DateTime.now().difference(savedAt) > maxAge) return null;
      return (record['items'] as List<dynamic>).map(BookListItem.decode).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> writeList(String name, List<BookListItem> items) => _store.write(
    '$homeContentCachePrefix$name',
    jsonEncode(<String, Object?>{
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'items': items.map((book) => book.encode()).toList(),
    }),
  );

  Future<void> clearHome() async {
    for (final name in <String>['ranking-daily', 'ranking-weekly', 'ranking-monthly', 'latest', 'comics']) {
      await _store.delete('$homeContentCachePrefix$name');
    }
  }

  Future<ShelfSnapshot?> readShelf() async {
    try {
      final raw = await _store.read(shelfSnapshotCacheKey);
      if (raw == null) return null;
      final record = jsonDecode(raw) as Map<String, dynamic>;
      return ShelfSnapshot(
        items: (record['items'] as List<dynamic>).map(ShelfItem.decode).toList(),
        books: (record['books'] as List<dynamic>).map(BookListItem.decode).toList(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> writeShelf(ShelfSnapshot snapshot) => _store.write(
    shelfSnapshotCacheKey,
    jsonEncode(<String, Object?>{
      'items': snapshot.items.map((item) => item.encode()).toList(),
      'books': snapshot.books.map((book) => book.encode()).toList(),
    }),
  );

  Future<({
    List<int> novel,
    List<int> comic,
    List<BookListItem> novelItems,
    List<BookListItem> comicItems,
  })?> readHistoryPreview() async {
    try {
      final raw = await _store.read(historyIndexCacheKey);
      if (raw == null) return null;
      final record = jsonDecode(raw) as Map<String, dynamic>;
      return (
        novel: (record['novel'] as List<dynamic>).cast<int>(),
        comic: (record['comic'] as List<dynamic>).cast<int>(),
        novelItems: (record['novelItems'] as List<dynamic>)
            .map(BookListItem.decode)
            .toList(),
        comicItems: (record['comicItems'] as List<dynamic>)
            .map(BookListItem.decode)
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> writeHistoryPreview({
    required List<int> novel,
    required List<int> comic,
    required List<BookListItem> novelItems,
    required List<BookListItem> comicItems,
  }) =>
      _store.write(
        historyIndexCacheKey,
        jsonEncode(<String, Object?>{
          'novel': novel,
          'comic': comic,
          'novelItems': novelItems.map((book) => book.encode()).toList(),
          'comicItems': comicItems.map((book) => book.encode()).toList(),
        }),
      );

  Future<UserProfile?> readProfile() async {
    try {
      final raw = await _store.read(profileCacheKey);
      return raw == null ? null : UserProfile.decode(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> writeProfile(UserProfile profile) =>
      _store.write(profileCacheKey, jsonEncode(profile.encode()));

  Future<void> clearDataViews() async {
    await clear();
    await clearHome();
    await _store.delete(shelfSnapshotCacheKey);
    await _store.delete(historyIndexCacheKey);
    await _store.delete(profileCacheKey);
    await _store.delete('lightnovel.cache.book-metadata.v1');
    await _store.delete('lightnovel.cache.shelf.v1');
    await _store.delete('lightnovel.cache.history-index.v1');
  }
}
