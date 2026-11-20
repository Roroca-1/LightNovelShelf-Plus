import 'package:flutter/material.dart';

import '../layout/book_grid_layout.dart';

/// 网格卡片的公共零件：书籍、文件夹、占位卡片共用的选中/排序蒙层与标题框。

/// 覆盖在封面上的多选与排序蒙层；选中优先于排序。
class GridSelectionOverlay extends StatelessWidget {
  const GridSelectionOverlay({
    super.key,
    required this.selected,
    required this.sorting,
  });

  final bool selected;
  final bool sorting;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
      final scrim = isDark
          ? colors.primaryContainer.withValues(alpha: 0.44)
          : colors.primary.withValues(alpha: 0.24);
      return DecoratedBox(
        decoration: BoxDecoration(
          color: scrim,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.primary, width: 3),
        ),
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.primary,
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: colors.shadow.withValues(alpha: 0.28),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.check_rounded,
                size: 24,
                color: colors.onPrimary,
              ),
            ),
          ),
        ),
      );
    }
    if (sorting) {
      return const ColoredBox(
        color: Color(0x7A000000),
        child: Center(
          child: Icon(Icons.drag_indicator, size: 36, color: Colors.white),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 固定高度的两行标题框，网格里每张卡片的总高度必须一致。
class GridTileTitle extends StatelessWidget {
  const GridTileTitle({super.key, required this.title, this.color});

  final String title;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: BookGridLayout.titleHeightFor(MediaQuery.textScalerOf(context)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Center(
        child: Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            height: 16 / 13,
            color: color ?? Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    ),
  );
}
