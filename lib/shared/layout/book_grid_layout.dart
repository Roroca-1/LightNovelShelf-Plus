import 'dart:math' as math;

import 'package:flutter/rendering.dart';

class BookGridLayout {
  const BookGridLayout({
    required this.columns,
    required this.tileWidth,
    required this.contentWidth,
    this.crossAxisSpacing = columnGap,
    this.mainAxisSpacing = rowGap,
  });

  static const double columnGap = 10;
  static const double rowGap = 12;
  static const double horizontalPadding = 20;
  static const double coverAspectRatio = 2 / 3;
  // 桌面端会按系统 DPI 放大文字；40 在 108% 以上会让两行标题溢出。
  static const double titleBoxHeight = 52;

  final int columns;
  final double tileWidth;
  final double contentWidth;
  final double crossAxisSpacing;
  final double mainAxisSpacing;

  static int columnsFor(double contentWidth) {
    // 宽屏封面最大 140 逻辑像素；窗口变宽时增加列数，不放大封面。
    if (contentWidth >= 600) {
      return ((contentWidth + 24) / (140 + 24)).ceil();
    }
    if (contentWidth >= 480) return 4;
    return 3;
  }

  factory BookGridLayout.of(
    double windowWidth, {
    double horizontalPadding = BookGridLayout.horizontalPadding,
  }) {
    final contentWidth = math.max(1.0, windowWidth - 2 * horizontalPadding);
    final columns = columnsFor(contentWidth);
    final gap = contentWidth >= 600 ? 24.0 : columnGap;
    final tileWidth = ((contentWidth - (columns - 1) * gap) / columns)
        .floorToDouble();
    return BookGridLayout(
      columns: columns,
      tileWidth: tileWidth,
      contentWidth: contentWidth,
      crossAxisSpacing: gap,
      mainAxisSpacing: contentWidth >= 600 ? 24 : rowGap,
    );
  }

  /// 封面区高度（不含标题区），也是向图床请求尺寸档的依据。
  double get coverHeight => tileWidth / coverAspectRatio;

  // 额外空间吸收桌面端字体缩放、像素取整以及 InkWell 焦点描边。
  double get tileHeight => coverHeight + titleBoxHeight + 16;

  /// 骨架屏单块高度：封面 + 7 间距 + 两条 13 高的文本占位 + 4 间距。
  double get skeletonTileHeight => coverHeight + 7 + 13 + 4 + 13;

  int skeletonCount(double windowHeight, {double headerOffset = 110}) {
    final rows = math.max(
      1,
      ((windowHeight - headerOffset) / (skeletonTileHeight + mainAxisSpacing))
          .ceil(),
    );
    return rows * columns;
  }

  /// 加载更多时补齐残行并额外追加一整行骨架。
  int loadMorePlaceholderCount(int itemCount) =>
      ((columns - itemCount % columns) % columns) + columns;

  double get childAspectRatio => tileWidth / tileHeight;

  /// 卡片网格：`childAspectRatio` 按卡片实际高度。
  SliverGridDelegate tileGridDelegate({double? mainAxisSpacing}) =>
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing ?? this.mainAxisSpacing,
        mainAxisExtent: tileHeight,
      );

  /// 骨架网格：骨架卡片比真实卡片矮，用 `skeletonTileHeight`。
  SliverGridDelegate skeletonGridDelegate({double? mainAxisSpacing}) =>
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing ?? this.mainAxisSpacing,
        childAspectRatio: tileWidth / skeletonTileHeight,
      );
}
