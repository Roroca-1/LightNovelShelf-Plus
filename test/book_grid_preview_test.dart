import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel_shelf_plus/data/api/models.dart';
import 'package:lightnovel_shelf_plus/features/discover/widgets/book_grid.dart';
import 'package:lightnovel_shelf_plus/shared/widgets/book_cover_grid_item.dart';

void main() {
  testWidgets('桌面和平板封面保持舒适尺寸，两行完整可见且无溢出', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    final books = List.generate(
      40,
      (index) => BookListItem(
        id: index,
        type: null,
        title: '测试书名 $index',
        seriesTitle: null,
        coverUrl: '',
        coverPlaceholder: null,
        authorName: null,
        lastUpdatedAt: DateTime(2026),
        level: null,
        interiorLevel: null,
        category: null,
      ),
    );
    for (final width in <double>[800, 1280, 1920]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(32),
                child: BookGridPreview(books: books, onOpen: (_) {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tiles = find.byType(BookCoverGridItem);
      final first = tester.getRect(tiles.first);
      final last = tester.getRect(tiles.last);
      expect(first.width, greaterThanOrEqualTo(160));
      expect(last.bottom, lessThan(800));
      expect(last.right, lessThanOrEqualTo(width - 32));
      if (width == 1280) expect(tiles, findsNWidgets(12));
      expect(tester.takeException(), isNull);
    }
  });
}
