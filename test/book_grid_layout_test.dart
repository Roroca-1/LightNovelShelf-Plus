import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel_shelf_plus/shared/layout/book_grid_layout.dart';

void main() {
  test('标题高度随系统字号增大，封面比例保持不变', () {
    final regular = BookGridLayout.of(1280);
    final large = BookGridLayout.of(1280, textScaler: TextScaler.linear(2));
    expect(regular.titleHeight, 40);
    expect(large.titleHeight, 72);
    expect(large.coverHeight, regular.coverHeight);
    expect(large.tileHeight - regular.tileHeight, 32);
  });

  test('手机保留三列，平板和桌面保持舒适封面尺寸', () {
    expect(BookGridLayout.of(390).columns, 3);
    expect(BookGridLayout.of(800).columns, 4);
    expect(BookGridLayout.of(1100).columns, 5);
    expect(BookGridLayout.of(1280).columns, 6);
  });

  test('调整窗口宽度后卡片不会溢出，骨架与正文横向对齐', () {
    for (final width in <double>[
      320,
      390,
      520,
      639,
      640,
      800,
      1100,
      1280,
      1920,
    ]) {
      final layout = BookGridLayout.of(width);
      expect(layout.tileWidth, greaterThan(0));
      if (layout.contentWidth >= 600) {
        expect(layout.tileWidth, greaterThanOrEqualTo(120));
        expect(layout.coverHeight, greaterThanOrEqualTo(180));
      }
      expect(
        layout.columns * layout.tileWidth +
            (layout.columns - 1) * layout.crossAxisSpacing,
        lessThanOrEqualTo(layout.contentWidth),
      );
      final tiles =
          layout.tileGridDelegate()
              as SliverGridDelegateWithFixedCrossAxisCount;
      final skeleton =
          layout.skeletonGridDelegate()
              as SliverGridDelegateWithFixedCrossAxisCount;
      expect(skeleton.crossAxisCount, tiles.crossAxisCount);
      expect(skeleton.crossAxisSpacing, tiles.crossAxisSpacing);
      expect(skeleton.mainAxisSpacing, tiles.mainAxisSpacing);
    }
  });

  test('宽屏留白增加，分页占位补齐整行', () {
    final layout = BookGridLayout.of(1100);
    expect(layout.crossAxisSpacing, 24);
    expect(layout.mainAxisSpacing, 12);
    expect((7 + layout.loadMorePlaceholderCount(7)) % layout.columns, 0);
  });
}
