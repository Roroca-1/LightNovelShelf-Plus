import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel_shelf_plus/app/theme/app_theme.dart';
import 'package:lightnovel_shelf_plus/data/settings/app_settings.dart';
import 'package:lightnovel_shelf_plus/shared/widgets/grid_tile_parts.dart';

void main() {
  testWidgets('GridSelectionOverlay follows light and dark theme ColorScheme', (
    tester,
  ) async {
    Future<void> pumpWith(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: SizedBox(
              width: 120,
              height: 180,
              child: GridSelectionOverlay(selected: true, sorting: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final lightTheme = buildAppTheme(
      brightness: Brightness.light,
      settings: const AppSettings(
        useSystemColor: false,
        seedColorValue: '#00695C',
      ),
    );
    await pumpWith(lightTheme);

    var decorated = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(GridSelectionOverlay),
            matching: find.byType(DecoratedBox),
          ),
        )
        .toList();
    expect(decorated, hasLength(2));

    var frame = decorated[0].decoration as BoxDecoration;
    var badge = decorated[1].decoration as BoxDecoration;
    var icon = tester.widget<Icon>(find.byIcon(Icons.check_rounded));

    expect(frame.color, lightTheme.colorScheme.primary.withValues(alpha: 0.24));
    expect((frame.border! as Border).top.color, lightTheme.colorScheme.primary);
    expect(badge.color, lightTheme.colorScheme.primary);
    expect(icon.color, lightTheme.colorScheme.onPrimary);

    final darkTheme = buildAppTheme(
      brightness: Brightness.dark,
      settings: const AppSettings(
        useSystemColor: false,
        seedColorValue: '#1565C0',
        oledBlack: true,
      ),
    );
    await pumpWith(darkTheme);

    decorated = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(GridSelectionOverlay),
            matching: find.byType(DecoratedBox),
          ),
        )
        .toList();
    frame = decorated[0].decoration as BoxDecoration;
    badge = decorated[1].decoration as BoxDecoration;
    icon = tester.widget<Icon>(find.byIcon(Icons.check_rounded));

    expect(
      frame.color,
      darkTheme.colorScheme.primaryContainer.withValues(alpha: 0.44),
    );
    expect((frame.border! as Border).top.color, darkTheme.colorScheme.primary);
    expect(badge.color, darkTheme.colorScheme.primary);
    expect(icon.color, darkTheme.colorScheme.onPrimary);
  });
}
