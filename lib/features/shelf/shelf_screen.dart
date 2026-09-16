import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kana_kit/kana_kit.dart';
import 'package:pinyin/pinyin.dart';

import '../../data/api/models.dart';
import '../../core/platform/desktop_platform.dart';
import '../../data/api/requests.dart';
import '../../data/providers.dart';
import '../../data/repositories/shelf_draft.dart';
import '../../data/repositories/shelf_repository.dart';
import '../../data/repositories/local_comic_shelf_repository.dart';
import '../../data/settings/app_settings.dart';
import '../../data/session/auth_controller.dart';
import '../../shared/layout/book_grid_layout.dart';
import '../../shared/series_title.dart';
import '../../shared/paging/identity_child_delegate.dart';
import '../../shared/widgets/app_dialogs.dart';
import '../../shared/widgets/book_grid_slivers.dart';
import '../../shared/widgets/book_list_row.dart';
import '../../shared/widgets/state_views.dart';
import '../discover/widgets/novel_series_tile.dart';
import 'shelf_editor_controller.dart';
import 'shelf_series_books_screen.dart';
import 'widgets/shelf_manage_sheet.dart';
import 'widgets/shelf_tile.dart';

/// 书架页：根目录（`parents` 为空）与任意层级文件夹共用同一个界面。
class ShelfScreen extends ConsumerStatefulWidget {
  const ShelfScreen({super.key, this.parents = const <String>[]});

  /// 当前所在文件夹的完整路径（从根到当前层）。
  final List<String> parents;

  @override
  ConsumerState<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends ConsumerState<ShelfScreen> {
  final Map<String, String> _sortKeyCache = <String, String>{};
  static const KanaKit _kana = KanaKit();
  static final RegExp _kanaPattern = RegExp(r'[\u3040-\u30ff]');
  String? _selectionAnchor;
  ShelfItem? _focusedItem;
  final GlobalKey _selectionSurfaceKey = GlobalKey();
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};
  List<ShelfItem> _visibleSiblings = const <ShelfItem>[];
  Offset? _marqueeStart;
  Offset? _marqueeCurrent;
  Set<String> _marqueeBaseSelection = const <String>{};

  GlobalKey _itemKey(ShelfItem item) =>
      _itemKeys.putIfAbsent(item.key, GlobalKey.new);

  void _startMarquee(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    _marqueeStart = event.position;
    _marqueeCurrent = null;
    _marqueeBaseSelection =
        (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed)
            ? Set<String>.of(_state.selected)
            : const <String>{};
  }

  void _updateMarquee(PointerMoveEvent event) {
    final start = _marqueeStart;
    if (start == null || event.kind != PointerDeviceKind.mouse) return;
    if ((event.position - start).distance < 6 && _marqueeCurrent == null) return;
    final area = Rect.fromPoints(start, event.position);
    final selected = <ShelfItem>[];
    for (final item in _visibleSiblings) {
      if (!item.isBook || (item.bookId ?? -1) < 0) continue;
      final render = _itemKeys[item.key]?.currentContext?.findRenderObject();
      if (render is! RenderBox || !render.attached) continue;
      final itemRect = render.localToGlobal(Offset.zero) & render.size;
      if (area.overlaps(itemRect) || _marqueeBaseSelection.contains(item.key)) {
        selected.add(item);
      }
    }
    _editor.setSelection(selected);
    setState(() => _marqueeCurrent = event.position);
  }

  void _endMarquee(PointerEvent event) {
    if (_marqueeStart == null) return;
    setState(() {
      _marqueeStart = null;
      _marqueeCurrent = null;
      _marqueeBaseSelection = const <String>{};
    });
  }

  Widget _selectionSurface(Widget child) {
    final surface = _selectionSurfaceKey.currentContext?.findRenderObject();
    final start = _marqueeStart;
    final current = _marqueeCurrent;
    Rect? localRect;
    if (surface is RenderBox && start != null && current != null) {
      localRect = Rect.fromPoints(
        surface.globalToLocal(start),
        surface.globalToLocal(current),
      );
    }
    final colors = Theme.of(context).colorScheme;
    return Listener(
      onPointerDown: _startMarquee,
      onPointerMove: _updateMarquee,
      onPointerUp: _endMarquee,
      onPointerCancel: _endMarquee,
      child: Stack(
        key: _selectionSurfaceKey,
        children: <Widget>[
          Positioned.fill(child: child),
          if (localRect != null)
            Positioned.fromRect(
              rect: localRect,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    border: Border.all(color: colors.primary, width: 1.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _modifiedSelect(ShelfItem item, List<ShelfItem> siblings, bool shift) {
    if (shift && _selectionAnchor != null) {
      final start = siblings.indexWhere((entry) => entry.key == _selectionAnchor);
      final end = siblings.indexWhere((entry) => entry.key == item.key);
      if (start >= 0 && end >= 0) {
        final low = start < end ? start : end;
        final high = start > end ? start : end;
        _editor.setSelection(siblings.sublist(low, high + 1));
        return;
      }
    }
    _selectionAnchor = item.key;
    if (_state.mode != ShelfMode.select) {
      _editor.beginSelection(item);
    } else {
      _editor.toggleSelection(item);
    }
  }

  ShelfSortSetting get _sort => ref.read(appSettingsProvider).shelfSort;

  bool get _seriesView =>
      ref.read(appSettingsProvider).shelfSeriesView;

  BookDisplayMode get _displayMode =>
      ref.read(appSettingsProvider).shelfDisplayMode;

  void _setSort(ShelfSortSetting value) {
    _sortKeyCache.clear();
    ref
        .read(settingsControllerProvider)
        .update((settings) => settings.copyWith(shelfSort: value));
  }

  List<String> get _parents => widget.parents;

  String get _editorKey => shelfEditorKey(_parents);

  ShelfEditorController get _editor =>
      ref.read(shelfEditorProvider(_editorKey).notifier);

  ShelfEditorState get _state => ref.read(shelfEditorProvider(_editorKey));

  String _titleSortKey(String title) => _sortKeyCache.putIfAbsent(title, () {
    final normalized = title.trim().toLowerCase();
    if (normalized.isEmpty) return normalized;
    if (_kanaPattern.hasMatch(normalized)) {
      return _kana.toRomaji(normalized).toLowerCase();
    }
    return PinyinHelper.getPinyin(normalized, separator: '').toLowerCase();
  });

  String _itemTitle(ShelfItem item, ShelfLevel level) =>
      item.isBook ? level.bookById[item.bookId]?.title ?? '' : item.title;

  DateTime _addedAt(ShelfItem item) =>
      DateTime.tryParse(item.updatedAt) ??
      DateTime.fromMillisecondsSinceEpoch(0);

  DateTime _updatedAt(ShelfItem item, ShelfLevel level) => item.isBook
      ? level.bookById[item.bookId]?.lastUpdatedAt ?? _addedAt(item)
      : _addedAt(item);

  int _compareShelfItems(ShelfItem left, ShelfItem right, ShelfLevel level) {
    if (left.isBook != right.isBook) return left.isBook ? 1 : -1;
    final titleOrder = _titleSortKey(_itemTitle(left, level))
        .compareTo(_titleSortKey(_itemTitle(right, level)));
    final order = switch (_sort) {
      ShelfSortSetting.manual => left.index.compareTo(right.index),
      ShelfSortSetting.titleAscending => titleOrder,
      ShelfSortSetting.titleDescending => -titleOrder,
      ShelfSortSetting.updatedNewest => _updatedAt(
        right,
        level,
      ).compareTo(_updatedAt(left, level)),
      ShelfSortSetting.updatedOldest => _updatedAt(
        left,
        level,
      ).compareTo(_updatedAt(right, level)),
      ShelfSortSetting.addedNewest => _addedAt(right).compareTo(_addedAt(left)),
    };
    return order != 0 ? order : titleOrder;
  }

  List<ShelfItem> _sortedSiblings(ShelfLevel level) {
    if (_sort == ShelfSortSetting.manual) return level.siblings;
    return List<ShelfItem>.of(level.siblings)
      ..sort((left, right) => _compareShelfItems(left, right, level));
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await _editor.save();
    if (!saved || !mounted) return;
    messenger.showText('书架已保存');
  }

  /// 放弃草稿；有改动时先确认，返回是否已经放弃。
  Future<bool> _discard() async {
    if (_state.draft == null) return true;
    final snapshot = ref.read(shelfProvider).value;
    if (snapshot != null && _editor.isDirty(snapshot)) {
      final ok = await showAppConfirm(
        context: context,
        title: '放弃修改',
        message: '书架的改动尚未保存，离开将丢失这些修改。',
        confirmLabel: '放弃',
      );
      if (!ok || !mounted) return false;
    }
    _editor.discard();
    return true;
  }

  /// 选择移动目标；返回空列表代表根文件夹，返回 null 代表取消。
  Future<List<String>?> _pickDestination(ShelfDraft draft) {
    final editor = _editor;
    final destinations = <(String label, List<String> path)>[
      if (_parents.isNotEmpty) ('根文件夹', const <String>[]),
      for (final folder in shelfFolderPaths(draft))
        if (!editor.isCurrentPath(folder.path))
          (editor.pathLabel(draft, folder.path), folder.path),
    ];
    if (destinations.isEmpty) {
      editor.reportError('还没有可用的目标文件夹，请先新建一个。');
      return Future<List<String>?>.value();
    }
    return showAppChoice<List<String>>(
      context: context,
      title: '移动到文件夹',
      options: destinations,
    );
  }

  ShelfManageCommand get _modeCommand => switch (_state.mode) {
    ShelfMode.browse => ShelfManageCommand.browse,
    ShelfMode.select => ShelfManageCommand.select,
    ShelfMode.drag => ShelfManageCommand.drag,
  };

  Future<void> _openManageSheet() async {
    final snapshot = ref.read(shelfProvider).value;
    if (snapshot == null) return;
    final editor = _editor;
    final dirty = editor.isDirty(snapshot);
    final command = await ShelfManageSheet.show(
      context,
      activeMode: _modeCommand,
      commands: <ShelfManageCommand>[
        ShelfManageCommand.browse,
        ShelfManageCommand.drag,
        ShelfManageCommand.select,
        if (_state.selected.isNotEmpty) ShelfManageCommand.removeItems,
        if (dirty) ShelfManageCommand.save,
        if (dirty) ShelfManageCommand.discard,
      ],
    );
    if (command == null || !mounted) return;
    await _runCommand(command);
  }

  Future<void> _runCommand(ShelfManageCommand command) async {
    switch (command) {
      case ShelfManageCommand.browse:
        _editor.setMode(ShelfMode.browse);
      case ShelfManageCommand.drag:
        _editor.setMode(ShelfMode.drag);
      case ShelfManageCommand.select:
        _editor.setMode(ShelfMode.select);
      case ShelfManageCommand.createFolder:
        await _createFolder();
      case ShelfManageCommand.renameFolder:
        await _renameFolder();
      case ShelfManageCommand.deleteFolder:
        await _deleteFolders();
      case ShelfManageCommand.moveBooks:
        await _moveBooks();
      case ShelfManageCommand.removeItems:
        await _removeItems();
      case ShelfManageCommand.save:
        await _save();
      case ShelfManageCommand.discard:
        await _discard();
    }
  }

  Future<void> _createFolder() async {
    final name = await showAppTextPrompt(
      context: context,
      title: '新建文件夹',
      hint: '请输入文件夹名称',
    );
    if (name == null || !mounted) return;
    _editor.createFolder(name);
  }

  Future<void> _renameFolder() async {
    final snapshot = ref.read(shelfProvider).value;
    if (snapshot == null) return;
    final editor = _editor;
    final folders = editor.selectedFolders(editor.effectiveDraft(snapshot));
    if (folders.length != 1) return;
    final folder = folders.single;
    final name = await showAppTextPrompt(
      context: context,
      title: '重命名文件夹',
      hint: '请输入文件夹名称',
      initial: folder.title,
    );
    if (name == null || !mounted) return;
    editor.renameFolder(folder.folderId!, name);
  }

  Future<void> _deleteFolders() async {
    final snapshot = ref.read(shelfProvider).value;
    if (snapshot == null) return;
    final editor = _editor;
    final folders = editor.selectedFolders(editor.effectiveDraft(snapshot));
    if (folders.isEmpty) return;
    final ok = await showAppConfirm(
      context: context,
      title: '删除文件夹',
      message: '将删除所选的 ${folders.length} 个文件夹，其中的书籍会移回书架根目录。',
      confirmLabel: '删除',
    );
    if (!ok || !mounted) return;
    editor.deleteFolders(folders);
  }

  Future<void> _moveBooks() async {
    final snapshot = ref.read(shelfProvider).value;
    if (snapshot == null) return;
    final editor = _editor;
    final draft = editor.effectiveDraft(snapshot);
    final books = editor.selectedBooks(draft);
    if (books.isEmpty) return;
    final destination = await _pickDestination(draft);
    if (destination == null || !mounted) return;
    editor.moveBooks(
      bookIds: books.map((item) => item.bookId!).toList(),
      destination: destination,
    );
  }

  Future<void> _removeItems() async {
    final snapshot = ref.read(shelfProvider).value;
    final selected = _state.selected;
    if (snapshot == null || selected.isEmpty) return;
    final editor = _editor;
    final draft = editor.effectiveDraft(snapshot);
    final ids = editor.selectedBooks(draft).map((item) => item.bookId!).toSet();
    if (ids.isEmpty) return;
    final ok = await showAppConfirm(
      context: context,
      title: '移出书架',
      message: '将从书架移出 ${ids.length} 本书，阅读记录不受影响。',
      confirmLabel: '移出',
    );
    if (!ok || !mounted) return;
    try {
      final removed = await ref.read(shelfProvider.notifier).removeBooks(ids);
      editor.setMode(ShelfMode.browse);
      if (mounted) ScaffoldMessenger.of(context).showText('已从书架移出 $removed 本书');
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showText(describeShelfError(error, fallback: '无法移出所选书籍。'));
    }
  }

  void _openFolder(String folderId) {
    final uri = Uri(
      path: '/shelf/folder',
      queryParameters: <String, List<String>>{
        'parent': <String>[..._parents, folderId],
      },
    );
    context.push(uri.toString());
  }

  void _openBook(BookListItem book) {
    context.push('/book/${book.id}');
  }

  Future<void> _showBookMenu(BookListItem book, Offset position) async {
    final item = ref
        .read(shelfProvider)
        .value
        ?.items
        .where((entry) => entry.bookId == book.id)
        .firstOrNull;
    final selectedCount = _state.selected.length;
    final isBatch = item != null &&
        selectedCount > 1 &&
        _state.selected.contains(item.key);
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final local = overlay.globalToLocal(position);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(local.dx, local.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        const PopupMenuItem(value: 'read', child: ListTile(leading: Icon(Icons.play_arrow), title: Text('阅读'))),
        if (book.type == BookType.novel)
          const PopupMenuItem(value: 'series', child: ListTile(leading: Icon(Icons.library_books_outlined), title: Text('搜索系列'))),
        const PopupMenuItem(enabled: false, child: ListTile(leading: Icon(Icons.bookmark_added_outlined), title: Text('已在书架'))),
        PopupMenuItem(
          value: 'remove',
          child: ListTile(
            leading: const Icon(Icons.remove_circle_outline),
            title: Text(isBatch ? '移出所选 $selectedCount 项' : '移出书架'),
          ),
        ),
        const PopupMenuItem(value: 'select', child: ListTile(leading: Icon(Icons.checklist_outlined), title: Text('多选'))),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'read':
        context.push('/reader/${book.id}/1${book.type == BookType.comic ? '?type=Comic' : ''}');
      case 'series':
        context.push(Uri(path: '/books/series', queryParameters: <String, String>{'name': seriesTitleFromBookTitle(book.title), 'order': BookListOrder.latest.wire}).toString());
      case 'remove':
        if (isBatch) {
          await _removeItems();
        } else {
          await ref.read(shelfProvider.notifier).removeBooks(<int>[book.id]);
        }
      case 'select':
        if (item != null) _editor.beginSelection(item);
    }
  }

  void _openShelfSeries(String name, List<BookListItem> books) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => ShelfSeriesBooksScreen(
          seriesName: name,
          books: books,
          initialDisplayMode: _displayMode,
          onOpen: (pageContext, book) {
            Navigator.of(pageContext).pop();
            _openBook(book);
          },
        ),
      ),
    );
  }

  Widget _banner(
    String message, {
    required VoidCallback onAction,
    IconData actionIcon = Icons.close,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.error),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, size: 20, color: colors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 14,
                height: 19 / 14,
                color: colors.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: onAction,
            child: Icon(actionIcon, size: 20, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _selectionSummary(
    ShelfDraft draft,
    ShelfEditorState editor,
    List<ShelfItem> siblings,
  ) {
    final colors = Theme.of(context).colorScheme;
    final books = shelfSelectionBookCount(draft, editor.selected);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '已选择 ${editor.selected.length} 项 · 含 $books 本书',
              style: TextStyle(fontSize: 14, color: colors.onSurface),
            ),
          ),
          TextButton(
            onPressed: () => _editor.selectAll(siblings),
            child: const Text('全选'),
          ),
          IconButton(
            tooltip: '移出书架',
            onPressed: books == 0 ? null : _removeItems,
            icon: Icon(Icons.delete_outline, color: colors.error),
          ),
          TextButton(
            onPressed: () => _editor.setMode(ShelfMode.browse),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(
      appSettingsProvider.select(
        (settings) => (
          settings.shelfSort,
          settings.shelfSeriesView,
          settings.shelfDisplayMode,
        ),
      ),
    );
    final auth = ref.watch(authSnapshotProvider);
    final authenticated = auth.isAuthenticated ||
        (ref.read(appRuntimeProvider).hasStoredSession &&
            (auth.status == AuthenticationStatus.unknown ||
                auth.status == AuthenticationStatus.refreshing));
    final async = ref.watch(shelfProvider);
    final editor = ref.watch(shelfEditorProvider(_editorKey));
    final snapshot = async.value;
    final localComics = ref.watch(localComicShelfProvider).value ??
        const <LocalShelfComic>[];
    final controller = _editor;
    final dirty = snapshot != null && controller.isDirty(snapshot);
    final draft = snapshot == null ? null : controller.effectiveDraft(snapshot);
    final title = _parents.isEmpty || draft == null
        ? '书架'
        : controller.folderTitle(draft, _parents.last);

    return PopScope<Object?>(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discarded = await _discard();
        if (!discarded || !context.mounted) return;
        if (context.canPop()) context.pop();
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (!isDesktopPlatform) return KeyEventResult.ignored;
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            if (editor.mode == ShelfMode.select) {
              controller.setMode(ShelfMode.browse);
              return KeyEventResult.handled;
            }
            if (context.canPop()) context.pop();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.space &&
              _focusedItem != null) {
            final item = _focusedItem!;
            if (editor.mode == ShelfMode.select) {
              controller.toggleSelection(item);
            } else {
              controller.beginSelection(item);
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.keyA &&
              (HardwareKeyboard.instance.isControlPressed ||
                  HardwareKeyboard.instance.isMetaPressed) &&
              _visibleSiblings.isNotEmpty) {
            controller.setSelection(
              _visibleSiblings.where((item) => item.isBook),
            );
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: <Widget>[
            if (snapshot != null && editor.mode == ShelfMode.browse)
              _ShelfSortMenu(value: _sort, onChanged: _setSort),
            if (snapshot != null && editor.mode == ShelfMode.browse)
              IconButton(
                tooltip: _seriesView ? '按单本显示' : '按系列显示',
                onPressed: () => ref
                    .read(settingsControllerProvider)
                    .update(
                      (settings) => settings.copyWith(
                        shelfSeriesView: !settings.shelfSeriesView,
                      ),
                    ),
                icon: Icon(
                  _seriesView
                      ? Icons.folder_outlined
                      : Icons.description_outlined,
                ),
              ),
            if (snapshot != null && editor.mode == ShelfMode.browse)
              IconButton(
                tooltip: _displayMode == BookDisplayMode.grid
                    ? '切换到列表视图'
                    : '切换到网格视图',
                onPressed: () => ref
                    .read(settingsControllerProvider)
                    .update(
                      (settings) => settings.copyWith(
                        shelfDisplayMode:
                            settings.shelfDisplayMode == BookDisplayMode.grid
                            ? BookDisplayMode.list
                            : BookDisplayMode.grid,
                      ),
                    ),
                icon: Icon(
                  _displayMode == BookDisplayMode.grid
                      ? Icons.view_list_outlined
                      : Icons.grid_view_outlined,
                ),
              ),
            if (dirty && !editor.saving)
              TextButton(onPressed: () => _discard(), child: const Text('取消')),
            if (dirty)
              editor.saving
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      ),
                    )
                  : TextButton(onPressed: _save, child: const Text('保存')),
            IconButton(
              tooltip: '管理书架',
              onPressed: snapshot == null ? null : _openManageSheet,
              icon: const Icon(Icons.more_vert),
            ),
          ],
        ),
        body: !authenticated
            ? EmptyStateView(
                icon: Icons.lock_outline,
                title: '登录后查看书架',
                description: '登录轻书架账号即可同步书架与阅读进度。',
                actionLabel: '去登录',
                onAction: () => context.go('/sign-in'),
              )
            : _selectionSurface(
                RefreshIndicator(
                  onRefresh: () => ref.read(shelfProvider.notifier).reload(),
                  child: _body(async, editor, snapshot, draft, localComics),
                ),
              ),
        ),
      ),
    );
  }

  Widget _body(
    AsyncValue<ShelfSnapshot?> async,
    ShelfEditorState editor,
    ShelfSnapshot? snapshot,
    ShelfDraft? draft,
    List<LocalShelfComic> localComics,
  ) {
    final media = MediaQuery.sizeOf(context);
    final layout = BookGridLayout.of(media.width);

    if (snapshot == null || draft == null) {
      if (async.hasError) {
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorStateView(
                message: describeShelfError(async.error!),
                onRetry: () => ref.read(shelfProvider.notifier).reload(),
              ),
            ),
          ],
        );
      }
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          bookGridSkeletonSliver(
            layout: layout,
            count: layout.skeletonCount(media.height, headerOffset: 120),
            padding: const EdgeInsets.fromLTRB(
              BookGridLayout.horizontalPadding,
              20,
              BookGridLayout.horizontalPadding,
              20,
            ),
          ),
        ],
      );
    }

    final level = _editor.level(snapshot, draft);
    final serverSiblings = editor.mode == ShelfMode.browse
        ? _sortedSiblings(level)
        : level.siblings;
    final localBooks = <int, BookListItem>{};
    final localItems = <ShelfItem>[];
    if (_parents.isEmpty && editor.mode == ShelfMode.browse) {
      for (final comic in localComics) {
        final localId = -comic.id;
        localBooks[localId] = comic.toBookListItem();
        localItems.add(
          ShelfItem.book(
            id: localId,
            index: -1,
            parents: const <String>[],
            updatedAt: comic.addedAt.toUtc().toIso8601String(),
          ),
        );
      }
    }
    final displayLevel = ShelfLevel(
      siblings: <ShelfItem>[...serverSiblings, ...localItems],
      bookById: <int, BookListItem>{...level.bookById, ...localBooks},
      folderPreviews: level.folderPreviews,
    );
    final siblings = _sort == ShelfSortSetting.manual
        ? displayLevel.siblings
        : (List<ShelfItem>.of(displayLevel.siblings)..sort(
            (left, right) => _compareShelfItems(left, right, displayLevel),
          ));
    _visibleSiblings = siblings;
    final refreshError = async.hasError
        ? describeShelfError(async.error!)
        : null;
    final editorError = editor.error;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            BookGridLayout.horizontalPadding,
            20,
            BookGridLayout.horizontalPadding,
            0,
          ),
          sliver: SliverList.list(
            children: <Widget>[
              if (_parents.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _editor.pathLabel(draft, _parents),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 19 / 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (editorError != null)
                _banner(editorError, onAction: () => _editor.clearError()),
              if (refreshError != null)
                _banner(
                  '刷新失败：$refreshError',
                  onAction: () => ref.read(shelfProvider.notifier).reload(),
                  actionIcon: Icons.refresh,
                ),
              if (editor.mode == ShelfMode.select)
                _selectionSummary(draft, editor, siblings),
              if (editor.mode == ShelfMode.drag)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    '长按书籍或文件夹拖动到目标位置，完成后点击保存。',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (siblings.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyStateView(
              icon: _parents.isEmpty
                  ? Icons.collections_bookmark_outlined
                  : Icons.folder_open_outlined,
              title: _parents.isEmpty ? '书架还是空的' : '这个文件夹是空的',
              description: _parents.isEmpty
                  ? '在书籍详情页点击“加入书架”，之后就能在这里找到它。'
                  : '把书籍移动到这个文件夹后会显示在这里。',
            ),
          )
        else if (_seriesView && editor.mode == ShelfMode.browse)
          _displayMode == BookDisplayMode.list
              ? _seriesList(displayLevel, siblings)
              : _seriesGrid(displayLevel, layout, siblings)
        else if (_displayMode == BookDisplayMode.list && editor.mode != ShelfMode.drag)
          _bookList(displayLevel, siblings)
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              BookGridLayout.horizontalPadding,
              0,
              BookGridLayout.horizontalPadding,
              32,
            ),
            sliver: SliverGrid(
              gridDelegate: layout.tileGridDelegate(
                mainAxisSpacing: editor.mode == ShelfMode.drag ? 18 : null,
              ),
              delegate: IdentityChildDelegate<ShelfItem>(
                items: siblings,
                revision: (level, layout.tileWidth),
                itemBuilder: (_, item, index) => KeyedSubtree(
                  key: _itemKey(item),
                  child: ShelfTile(
                    editorKey: _editorKey,
                    item: item,
                    index: index,
                    siblings: siblings,
                    book: item.isBook
                        ? displayLevel.bookById[item.bookId]
                        : null,
                    folder: item.isBook
                        ? null
                        : level.folderPreviews[item.folderId],
                    tileWidth: layout.tileWidth,
                    onOpenBook: _openBook,
                    onOpenFolder: _openFolder,
                    selectable: (item.bookId ?? 0) >= 0,
                    onBookContextMenu: _showBookMenu,
                    onModifiedSelection: (item, shift) =>
                        _modifiedSelect(item, siblings, shift),
                    onFocusChange: (focused) {
                      if (focused) _focusedItem = item;
                    },
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _bookList(ShelfLevel level, List<ShelfItem> siblings) =>
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          BookGridLayout.horizontalPadding,
          0,
          BookGridLayout.horizontalPadding,
          32,
        ),
        sliver: SliverList.separated(
          itemCount: siblings.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = siblings[index];
            if (item.isBook) {
              final book = level.bookById[item.bookId];
              if (book == null) {
                return const Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(Icons.book_outlined),
                    title: Text('书籍已下架'),
                  ),
                );
              }
              final selected = _state.selected.contains(item.key);
              return KeyedSubtree(
                key: _itemKey(item),
                child: CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.space): () {
                      if (_state.mode == ShelfMode.select) {
                        _editor.toggleSelection(item);
                      } else {
                        _editor.beginSelection(item);
                      }
                    },
                  },
                  child: BookListRow(
                    book: book,
                    onSecondaryTap: (position) => _showBookMenu(book, position),
                    selected: selected,
                    onLongPress: () => _editor.beginSelection(item),
                    onFocusChange: (focused) {
                      if (focused) _focusedItem = item;
                    },
                    onTap: () => _state.mode == ShelfMode.select
                        ? _editor.toggleSelection(item)
                        : (HardwareKeyboard.instance.isControlPressed ||
                                  HardwareKeyboard.instance.isMetaPressed ||
                                  HardwareKeyboard.instance.isShiftPressed)
                            ? _modifiedSelect(
                                item,
                                siblings,
                                HardwareKeyboard.instance.isShiftPressed,
                              )
                            : _openBook(book),
                  ),
                ),
              );
            }
            final title = item.title.trim();
            return Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                onTap: () => _openFolder(item.folderId!),
                leading: const Icon(Icons.folder_outlined),
                title: Text(title.isEmpty ? '未命名文件夹' : title),
                subtitle: Text(
                  '${level.folderPreviews[item.folderId]?.count ?? 0} 本书',
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
            );
          },
        ),
      );

  Widget _seriesList(ShelfLevel level, List<ShelfItem> siblings) {
    final grouped = <String, List<BookListItem>>{};
    final entries = <Object>[];
    for (final item in siblings) {
      final book = item.isBook ? level.bookById[item.bookId] : null;
      final name = book?.type == BookType.novel
          ? shelfSeriesKey(book!.title, book.seriesTitle)
          : null;
      if (book == null || name == null || name.isEmpty) {
        entries.add(item);
        continue;
      }
      grouped.putIfAbsent(name, () {
        entries.add(name);
        return <BookListItem>[];
      }).add(book);
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        BookGridLayout.horizontalPadding,
        0,
        BookGridLayout.horizontalPadding,
        32,
      ),
      sliver: SliverList.separated(
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final entry = entries[index];
          if (entry is! String) {
            final item = entry as ShelfItem;
            if (!item.isBook) {
              final title = item.title.trim();
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  onTap: () => _openFolder(item.folderId!),
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(title.isEmpty ? '未命名文件夹' : title),
                  subtitle: Text(
                    '${level.folderPreviews[item.folderId]?.count ?? 0} 本书',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                ),
              );
            }
            final book = level.bookById[item.bookId];
            return book == null
                ? const SizedBox.shrink()
                : BookListRow(book: book, onTap: () => _openBook(book));
          }
          final books = grouped[entry]!;
          final latest = books.reduce(
            (left, right) => left.lastUpdatedAt.isAfter(right.lastUpdatedAt)
                ? left
                : right,
          );
          final series = BookListItem(
            id: latest.id,
            type: BookType.novel,
            title: entry,
            seriesTitle: entry,
            coverUrl: latest.coverUrl,
            coverPlaceholder: latest.coverPlaceholder,
            authorName: latest.authorName,
            lastUpdatedAt: latest.lastUpdatedAt,
            level: null,
            interiorLevel: null,
            category: null,
          );
          return BookListRow(
            book: series,
            subtitle: [
              if (latest.authorName?.trim().isNotEmpty == true) latest.authorName!.trim(),
              '${books.length} 本',
              '更新于 ${latest.lastUpdatedAt.year}-${latest.lastUpdatedAt.month.toString().padLeft(2, '0')}-${latest.lastUpdatedAt.day.toString().padLeft(2, '0')}',
            ].join(' · '),
            onTap: () => _openShelfSeries(entry, books),
          );
        },
      ),
    );
  }

  Widget _seriesGrid(
    ShelfLevel level,
    BookGridLayout layout,
    List<ShelfItem> siblings,
  ) {
    final grouped = <String, List<BookListItem>>{};
    final entries = <Object>[];
    for (final item in siblings) {
      if (!item.isBook) {
        entries.add(item);
        continue;
      }
      final book = level.bookById[item.bookId];
      final name = book?.type == BookType.novel
          ? shelfSeriesKey(book!.title, book.seriesTitle)
          : null;
      if (book == null || name == null || name.isEmpty) {
        entries.add(item);
        continue;
      }
      final books = grouped.putIfAbsent(name, () {
        entries.add(name);
        return <BookListItem>[];
      });
      books.add(book);
    }

    if (_sort != ShelfSortSetting.manual) {
      String titleOf(Object entry) =>
          entry is String ? entry : _itemTitle(entry as ShelfItem, level);
      DateTime addedAt(Object entry) => entry is String
          ? grouped[entry]!
                .map(
                  (book) => siblings.firstWhere(
                    (item) => item.isBook && item.bookId == book.id,
                  ),
                )
                .map(_addedAt)
                .reduce((left, right) => left.isAfter(right) ? left : right)
          : _addedAt(entry as ShelfItem);
      DateTime updatedAt(Object entry) => entry is String
          ? grouped[entry]!
                .map((book) => book.lastUpdatedAt)
                .reduce((left, right) => left.isAfter(right) ? left : right)
          : _updatedAt(entry as ShelfItem, level);
      entries.sort((left, right) {
        final leftFolder = left is ShelfItem && !left.isBook;
        final rightFolder = right is ShelfItem && !right.isBook;
        if (leftFolder != rightFolder) return leftFolder ? -1 : 1;
        final titleOrder = _titleSortKey(titleOf(left))
            .compareTo(_titleSortKey(titleOf(right)));
        final order = switch (_sort) {
          ShelfSortSetting.manual => 0,
          ShelfSortSetting.titleAscending => titleOrder,
          ShelfSortSetting.titleDescending => -titleOrder,
          ShelfSortSetting.updatedNewest => updatedAt(
            right,
          ).compareTo(updatedAt(left)),
          ShelfSortSetting.updatedOldest => updatedAt(
            left,
          ).compareTo(updatedAt(right)),
          ShelfSortSetting.addedNewest => addedAt(right).compareTo(addedAt(left)),
        };
        return order != 0 ? order : titleOrder;
      });
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        BookGridLayout.horizontalPadding,
        0,
        BookGridLayout.horizontalPadding,
        32,
      ),
      sliver: SliverGrid(
        gridDelegate: layout.tileGridDelegate(),
        delegate: SliverChildBuilderDelegate((context, index) {
          final entry = entries[index];
          if (entry is String) {
            final books = grouped[entry]!;
            final latest = books.reduce(
              (left, right) => left.lastUpdatedAt.isAfter(right.lastUpdatedAt)
                  ? left
                  : right,
            );
            return NovelSeriesTile(
              series: NovelSeriesListItem(
                name: entry,
                coverUrl: latest.coverUrl,
                coverPlaceholder: latest.coverPlaceholder,
                bookCount: books.length,
                lastUpdatedAt: latest.lastUpdatedAt,
              ),
              coverHeight: layout.coverHeight,
              onTap: () => _openShelfSeries(entry, books),
            );
          }
          final item = entry as ShelfItem;
          return ShelfTile(
            editorKey: _editorKey,
            item: item,
            index: level.siblings.indexOf(item),
            siblings: level.siblings,
            book: item.isBook ? level.bookById[item.bookId] : null,
            folder: item.isBook ? null : level.folderPreviews[item.folderId],
            tileWidth: layout.tileWidth,
            onOpenBook: _openBook,
            onOpenFolder: _openFolder,
            selectable: (item.bookId ?? 0) >= 0,
          );
        }, childCount: entries.length),
      ),
    );
  }
}

class _ShelfSortMenu extends StatelessWidget {
  const _ShelfSortMenu({required this.value, required this.onChanged});

  final ShelfSortSetting value;
  final ValueChanged<ShelfSortSetting> onChanged;

  static const Map<ShelfSortSetting, String> _labels =
      <ShelfSortSetting, String>{
    ShelfSortSetting.manual: '手动顺序',
    ShelfSortSetting.titleAscending: '标题 A–Z（拼音/罗马字）',
    ShelfSortSetting.titleDescending: '标题 Z–A（拼音/罗马字）',
    ShelfSortSetting.updatedNewest: '最近更新',
    ShelfSortSetting.updatedOldest: '最早更新',
    ShelfSortSetting.addedNewest: '最近加入',
  };

  @override
  Widget build(BuildContext context) => PopupMenuButton<ShelfSortSetting>(
    tooltip: '书架排序',
    icon: const Icon(Icons.sort),
    position: PopupMenuPosition.under,
    onSelected: onChanged,
    itemBuilder: (_) => <PopupMenuEntry<ShelfSortSetting>>[
      for (final entry in _labels.entries)
        PopupMenuItem<ShelfSortSetting>(
          value: entry.key,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(entry.value),
            trailing: entry.key == value ? const Icon(Icons.check) : null,
          ),
        ),
    ],
  );
}
