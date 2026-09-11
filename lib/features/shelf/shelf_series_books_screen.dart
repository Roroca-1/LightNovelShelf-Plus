import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/models.dart';
import '../../data/repositories/shelf_repository.dart';
import '../../data/settings/app_settings.dart';
import '../../shared/layout/book_grid_layout.dart';
import '../../shared/paging/identity_child_delegate.dart';
import '../../shared/widgets/app_dialogs.dart';
import '../../shared/widgets/book_cover_grid_item.dart';
import '../../shared/widgets/book_context_menu.dart';
import '../../shared/widgets/book_list_row.dart';

/// 书架当前层中属于同一系列的小说。这里只展示已收藏的分卷。
class ShelfSeriesBooksScreen extends ConsumerStatefulWidget {
  const ShelfSeriesBooksScreen({
    super.key,
    required this.seriesName,
    required this.books,
    required this.initialDisplayMode,
    required this.onOpen,
  });

  final String seriesName;
  final List<BookListItem> books;
  final BookDisplayMode initialDisplayMode;
  final void Function(BuildContext context, BookListItem book) onOpen;

  @override
  ConsumerState<ShelfSeriesBooksScreen> createState() =>
      _ShelfSeriesBooksScreenState();
}

class _ShelfSeriesBooksScreenState
    extends ConsumerState<ShelfSeriesBooksScreen> {
  late List<BookListItem> _books = List<BookListItem>.of(widget.books)
    ..sort((left, right) => _naturalCompare(left.title, right.title));
  late BookDisplayMode _displayMode = widget.initialDisplayMode;
  final Set<int> _selected = <int>{};
  bool _removing = false;

  bool get _selecting => _selected.isNotEmpty;

  static int _naturalCompare(String left, String right) {
    final chunks = RegExp(r'\d+|\D+');
    final a = chunks.allMatches(left.toLowerCase()).map((m) => m[0]!).toList();
    final b = chunks.allMatches(right.toLowerCase()).map((m) => m[0]!).toList();
    for (var i = 0; i < a.length && i < b.length; i += 1) {
      final ai = int.tryParse(a[i]);
      final bi = int.tryParse(b[i]);
      final order = ai != null && bi != null
          ? ai.compareTo(bi)
          : a[i].compareTo(b[i]);
      if (order != 0) return order;
    }
    return a.length.compareTo(b.length);
  }

  void _toggle(BookListItem book) => setState(() {
    if (!_selected.remove(book.id)) _selected.add(book.id);
  });

  Future<void> _removeSelected() async {
    if (_removing || _selected.isEmpty) return;
    final count = _selected.length;
    final confirmed = await showAppConfirm(
      context: context,
      title: '移出书架',
      message: '将从书架移出所选的 $count 本书，阅读记录不受影响。',
      confirmLabel: '移出',
    );
    if (!confirmed || !mounted) return;
    setState(() => _removing = true);
    try {
      final removed = await ref
          .read(shelfProvider.notifier)
          .removeBooks(_selected);
      if (!mounted) return;
      final removedIds = Set<int>.of(_selected);
      setState(() {
        _books = _books
            .where((book) => !removedIds.contains(book.id))
            .toList();
        _selected.clear();
      });
      ScaffoldMessenger.of(context).showText('已从书架移出 $removed 本书');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showText(
        describeShelfError(error, fallback: '无法移出所选书籍。'),
      );
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = BookGridLayout.of(MediaQuery.sizeOf(context).width, textScaler: MediaQuery.textScalerOf(context));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selecting ? '已选择 ${_selected.length} 本' : widget.seriesName,
          overflow: TextOverflow.ellipsis,
        ),
        leading: _selecting
            ? IconButton(
                tooltip: '取消选择',
                onPressed: () => setState(() => _selected.clear()),
                icon: const Icon(Icons.close),
              )
            : null,
        actions: <Widget>[
          if (!_selecting)
            IconButton(
              tooltip: _displayMode == BookDisplayMode.grid ? '列表视图' : '网格视图',
              onPressed: () => setState(
                () => _displayMode = _displayMode == BookDisplayMode.grid
                    ? BookDisplayMode.list
                    : BookDisplayMode.grid,
              ),
              icon: Icon(
                _displayMode == BookDisplayMode.grid
                    ? Icons.view_list_outlined
                    : Icons.grid_view_outlined,
              ),
            ),
          if (_selecting) ...<Widget>[
            TextButton(
              onPressed: _removing
                  ? null
                  : () => setState(
                      () => _selected
                        ..clear()
                        ..addAll(_books.map((book) => book.id)),
                    ),
              child: const Text('全选'),
            ),
            _removing
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : IconButton(
                    tooltip: '移出书架',
                    onPressed: _removeSelected,
                    icon: const Icon(Icons.delete_outline),
                  ),
          ],
        ],
      ),
      body: CustomScrollView(
        slivers: <Widget>[
          if (_displayMode == BookDisplayMode.list)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                BookGridLayout.horizontalPadding,
                20,
                BookGridLayout.horizontalPadding,
                32,
              ),
              sliver: SliverList.separated(
                itemCount: _books.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final book = _books[index];
                  return BookListRow(
                    book: book,
                    selected: _selected.contains(book.id),
                    onSecondaryTap: (position) => showBookContextMenu(
                      context: context,
                      ref: ref,
                      book: book,
                      globalPosition: position,
                      onSelect: () => _toggle(book),
                    ),
                    onLongPress: () => _toggle(book),
                    onTap: () => _selecting
                        ? _toggle(book)
                        : widget.onOpen(context, book),
                  );
                },
              ),
            )
          else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              BookGridLayout.horizontalPadding,
              20,
              BookGridLayout.horizontalPadding,
              32,
            ),
            sliver: SliverGrid(
              gridDelegate: layout.tileGridDelegate(),
              delegate: IdentityChildDelegate<BookListItem>(
                items: _books,
                revision: (
                  layout.coverHeight,
                  _selected.length,
                  Object.hashAllUnordered(_selected),
                ),
                itemBuilder: (_, book, _) => BookCoverGridItem.fromBook(
                  book,
                  key: ValueKey<int>(book.id),
                  coverHeight: layout.coverHeight,
                  selected: _selected.contains(book.id),
                  onSecondaryTap: (position) => showBookContextMenu(
                    context: context,
                    ref: ref,
                    book: book,
                    globalPosition: position,
                    onSelect: () => _toggle(book),
                  ),
                  onLongPress: () => _toggle(book),
                  onTap: () => _selecting
                      ? _toggle(book)
                      : widget.onOpen(context, book),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
