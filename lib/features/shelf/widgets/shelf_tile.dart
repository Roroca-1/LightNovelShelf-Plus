import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/models.dart';
import '../../../data/repositories/shelf_draft.dart';
import '../../../data/repositories/shelf_repository.dart';
import '../../../shared/layout/book_grid_layout.dart';
import '../../../shared/widgets/book_cover_grid_item.dart';
import '../shelf_editor_controller.dart';
import 'shelf_folder_tile.dart';
import 'unavailable_book_tile.dart';

/// 书架卡片：只订阅自身选中态与拖拽模式，一次选中不再重建整屏卡片。
class ShelfTile extends ConsumerWidget {
  const ShelfTile({
    super.key,
    required this.parents,
    required this.item,
    required this.index,
    required this.siblings,
    required this.book,
    required this.folder,
    required this.tileWidth,
    required this.onOpenBook,
    required this.onOpenFolder,
    this.selectable = true,
    this.onBookContextMenu,
    this.onModifiedSelection,
    this.onFocusChange,
  });

  /// 所在层的完整路径，拖拽重排要告诉 controller 重排的是哪一层。
  final List<String> parents;
  final ShelfItem item;
  final int index;
  final List<ShelfItem> siblings;

  /// 书籍条目对应的书籍，已下架时为空。
  final BookListItem? book;

  /// 文件夹条目的封面预览，书籍条目为空。
  final ShelfFolderPreview? folder;
  final double tileWidth;
  final void Function(BookListItem book) onOpenBook;
  final void Function(String folderId) onOpenFolder;
  final bool selectable;
  final void Function(BookListItem book, Offset position)? onBookContextMenu;
  final void Function(ShelfItem item, bool shift)? onModifiedSelection;
  final ValueChanged<bool>? onFocusChange;

  /// 选择模式下点击是切换选中；`open` 为空表示条目已下架，只能被选中。
  void _handleTap(WidgetRef ref, VoidCallback? open) {
    if (!selectable) {
      open?.call();
      return;
    }
    final editor = ref.read(shelfEditorProvider.notifier);
    final keyboard = HardwareKeyboard.instance;
    if (selectable &&
        (keyboard.isControlPressed ||
            keyboard.isMetaPressed ||
            keyboard.isShiftPressed)) {
      onModifiedSelection?.call(item, keyboard.isShiftPressed);
      return;
    }
    if (ref.read(shelfEditorProvider).mode == ShelfMode.select) {
      editor.toggleSelection(item);
      return;
    }
    if (open == null) {
      editor.beginSelection(item);
      return;
    }
    open();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      shelfEditorProvider.select((state) => state.selected.contains(item.key)),
    );
    final sorting = ref.watch(
      shelfEditorProvider.select((state) => state.mode == ShelfMode.drag),
    );
    void beginSelection() =>
        ref.read(shelfEditorProvider.notifier).beginSelection(item);

    final Widget tile;
    if (item.isBook) {
      final resolved = book;
      if (resolved == null) {
        tile = UnavailableBookTile(
          selected: selected,
          sorting: sorting,
          onTap: () => _handleTap(ref, null),
          onLongPress: selectable ? beginSelection : () {},
        );
      } else {
        tile = BookCoverGridItem.fromBook(
          resolved,
          coverHeight: tileWidth / BookGridLayout.coverAspectRatio,
          selected: selected,
          sorting: sorting,
          onTap: () => _handleTap(ref, () => onOpenBook(resolved)),
          onLongPress: beginSelection,
          onSecondaryTap: onBookContextMenu == null
              ? null
              : (position) => onBookContextMenu!(resolved, position),
          onFocusChange: onFocusChange,
        );
      }
    } else {
      final preview = folder ?? ShelfFolderPreview.empty;
      final folderId = item.folderId!;
      final title = item.title.trim();
      tile = ShelfFolderTile(
        title: title.isEmpty ? '未命名文件夹' : title,
        covers: [
          for (final id in preview.bookIds)
            ?ref.read(shelfProvider).value?.bookById[id],
        ],
        bookCount: preview.bookCount,
        folderCount: preview.folderCount,
        selected: selected,
        sorting: sorting,
        onTap: () => _handleTap(ref, () => onOpenFolder(folderId)),
        onLongPress: beginSelection,
      );
    }

    final keyboardTile = CallbackShortcuts(
      bindings: selectable
          ? <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.space): () {
                if (ref.read(shelfEditorProvider).mode == ShelfMode.select) {
                  ref.read(shelfEditorProvider.notifier).toggleSelection(item);
                } else {
                  beginSelection();
                }
              },
            }
          : const <ShortcutActivator, VoidCallback>{},
      child: tile,
    );
    if (!sorting) return keyboardTile;
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => ref
          .read(shelfEditorProvider.notifier)
          .reorder(siblings, details.data, index, parents: parents),
      builder: (context, candidate, _) => LongPressDraggable<int>(
        data: index,
        delay: const Duration(milliseconds: 180),
        feedback: Material(
          type: MaterialType.transparency,
          child: Opacity(
            opacity: 0.9,
            child: SizedBox(width: tileWidth, child: tile),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: tile),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: candidate.isEmpty
                  ? Colors.transparent
                  : Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
          child: keyboardTile,
        ),
      ),
    );
  }
}
