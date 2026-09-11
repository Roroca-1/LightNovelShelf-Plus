import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/settings/app_settings.dart';
import '../../../shared/widgets/html/reader_content_style.dart';
import '../../../shared/widgets/html/html_source.dart';
import '../../../shared/widgets/reader_html_block.dart';
import '../reader_block_markup.dart';
import '../reader_pagination.dart';
import '../reader_page_turn.dart';
import '../reader_position.dart';
import 'reader_measure_box.dart';
import 'reader_page_body.dart';
import 'reader_tap_zone.dart';

final RegExp _spacedReaderTextBlock = RegExp(
  r'^\s*<(?:p|h[1-6])\b',
  caseSensitive: false,
);

double _readerBlockSpacing(
  ReaderBlock block,
  ReaderBlock? next,
  double lineSpace,
) {
  if (next == null || lineSpace <= 0) return 0;
  if (block is ReaderImageBlock) return 0;
  return _spacedReaderTextBlock.hasMatch(block.html) ? lineSpace : 0;
}

/// 一章正文及其排版参数。正文字形逐章混淆，字体各章不同，所以样式随章走。
class ReaderChapterContent {
  const ReaderChapterContent({
    required this.sortNum,
    required this.blocks,
    required this.style,
  });

  final int sortNum;
  final List<ReaderBlock> blocks;
  final ReaderContentStyle style;
}

/// 正文位置上报。`page`/`pages` 从 1 开始，滚动模式恒为 0。
/// 位置一律记在屏首那一栏上，所以自带该栏所属的 [sortNum]。
class ReaderContentPosition {
  const ReaderContentPosition({
    required this.sortNum,
    required this.tailSortNum,
    required this.locator,
    required this.progression,
    required this.page,
    required this.pages,
  });

  /// 屏首那一栏所属的章。
  final int sortNum;

  /// 屏尾那一栏所属的章；一屏只有一栏或没跨章时与 [sortNum] 相同。
  final int tailSortNum;

  final String locator;
  final double progression;
  final int page;
  final int pages;
}

/// 从阅读器外部触发正文前后翻页；未挂载或正文尚未就绪时操作会被忽略。
class ReaderContentController {
  _ReaderContentViewState? _state;

  void previousPage() => _state?._turnFromController(false);

  void nextPage() => _state?._turnFromController(true);

  void seekPage(int oneBasedPage) => _state?._seekPage(oneBasedPage);

  void seekProgress(double progression) => _state?._seekProgress(progression);

  void _attach(_ReaderContentViewState state) => _state = state;

  void _detach(_ReaderContentViewState state) {
    if (identical(_state, state)) _state = null;
  }
}

/// 原生正文视图。
///
/// 正文用 `HtmlWidget` 渲染，翻页与定位在 Flutter 侧完成：先把整章排进零尺寸的测量层，
/// 读出每个块的纵向区间与每行行顶，再按视口高度切页；翻页模式的每一页只摆落在该页区间的块
/// 并裁掉溢出。排版、视口、图片尺寸变化会重新测量，并把阅读位置定回当前 locator。
///
/// [chapters] 里的每一章各有自己的测量层，测完后首尾相接组成翻页条，跨章翻页即走到条上的
/// 下一栏，落定后由 [onChapterChanged] 通知上层挪动当前章。
///
/// 翻页条两端之外若还有章，各补一段加载栏：栏上转圈，并通过 [onNeedChapter] 请求上层把
/// 那一章接进来。请求只在加载栏真的露在当前屏上时发出，所以关掉预加载时，单页要翻到章尾
/// 之后才请求，双页则在右栏空出来的那一刻就请求。
class ReaderContentView extends StatefulWidget {
  const ReaderContentView({
    super.key,
    required this.chapters,
    required this.sortNum,
    required this.paged,
    required this.dualPage,
    this.centeredText = false,
    required this.padding,
    required this.restoreLocator,
    required this.restoreProgression,
    required this.restoreToken,
    required this.onPosition,
    required this.onTapCenter,
    required this.onChapterChanged,
    required this.onBoundary,
    required this.onNeedChapter,
    required this.onFootnote,
    required this.onReady,
    this.totalChapters = 0,
    this.failedChapters = const <int>{},
    this.controller,
    this.pageTurnAnimation = ReaderPageTurnAnimation.none,
  });

  final ReaderContentController? controller;

  /// 已备好的连续章节，按章号升序，必须含 [sortNum] 那一章。
  final List<ReaderChapterContent> chapters;

  /// 当前章章号。
  final int sortNum;

  ReaderChapterContent get chapter =>
      chapters.firstWhere((chapter) => chapter.sortNum == sortNum);

  /// 全书章数，0 表示未知。用来判断翻页条两端之外还有没有章可接。
  final int totalChapters;

  /// 取失败的章号，加载栏改摆重试块。
  final Set<int> failedChapters;

  final bool paged;

  /// 点击或外部控制器触发翻页时使用的动画；手势拖动仍由 [PageView] 处理。
  final ReaderPageTurnAnimation pageTurnAnimation;

  /// 翻页模式下是否把一屏拆成两栏，只在大屏横屏时真的分栏。
  final bool dualPage;
  final bool centeredText;

  /// 正文四周留白，翻页模式下上下留白作用在每一页上。
  final EdgeInsets padding;

  final String? restoreLocator;
  final double restoreProgression;

  /// 上层要求重新定位（目录跳转、章节按钮）时自增，视图据此丢掉当前位置，
  /// 改按 [restoreLocator]/[restoreProgression] 定位。翻页导致的切章不改动它。
  final int restoreToken;

  final ValueChanged<ReaderContentPosition> onPosition;
  final VoidCallback onTapCenter;

  /// 翻页条进入了另一章，上层据此挪动当前章，正文不重排。
  final ValueChanged<int> onChapterChanged;

  /// 滚动模式读到头还要继续翻，交给上层换章。
  final Val…32701 tokens truncated…nual => 0,
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
