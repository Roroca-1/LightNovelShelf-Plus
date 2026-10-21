import 'package:flutter/material.dart';

import '../../data/settings/app_settings.dart';

/// OLED 纯黑模式下的覆盖色。
class OledPalette {
  const OledPalette._();

  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF000000);
  static const Color card = Color(0xFF0E1014);
  static const Color surfaceContainerHighest = Color(0xFF1A1A1A);
  static const Color label = Color(0xFFEFEFEF);
  static const Color secondaryLabel = Color(0xFFC7C7C7);
  static const Color separator = Color(0xFF252525);
}

Color parseSeedColor(String value) {
  final hex = value.replaceFirst('#', '');
  return Color(int.parse('FF$hex', radix: 16));
}

/// [parseSeedColor] 的逆运算，产出 `#RRGGBB`。
String formatHexColor(Color color) {
  final rgb =
      ((color.r * 255).round() << 16) |
      ((color.g * 255).round() << 8) |
      (color.b * 255).round();
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Brightness resolveBrightness(ThemeSetting theme, Brightness platform) =>
    switch (theme) {
      ThemeSetting.light => Brightness.light,
      ThemeSetting.dark => Brightness.dark,
      ThemeSetting.system => platform,
    };

/// 按感知亮度在黑白之间挑前景色，阈值 186。
Color onAccentColor(Color accent) {
  final luminance =
      0.299 * (accent.r * 255) +
      0.587 * (accent.g * 255) +
      0.114 * (accent.b * 255);
  return luminance > 186 ? Colors.black : Colors.white;
}

/// 决定 `ThemeData` 的设置子集。根节点只订阅它，拖阅读器字号之类的写入就不会重建
/// `MaterialApp.router`。
@immutable
class AppPalette {
  const AppPalette({
    required this.useSystemColor,
    required this.seedColorValue,
    required this.oledBlack,
    required this.hasBackgroundImage,
  });

  static AppPalette of(AppSettings settings) => AppPalette(
    useSystemColor: settings.useSystemColor,
    seedColorValue: settings.seedColorValue,
    oledBlack: settings.oledBlack,
    hasBackgroundImage: settings.appBackground.path?.isNotEmpty == true,
  );

  final bool useSystemColor;
  final String seedColorValue;
  final bool oledBlack;
  final bool hasBackgroundImage;

  @override
  bool operator ==(Object other) =>
      other is AppPalette &&
      other.useSystemColor == useSystemColor &&
      other.seedColorValue == seedColorValue &&
      other.oledBlack == oledBlack &&
      other.hasBackgroundImage == hasBackgroundImage;

  @override
  int get hashCode => Object.hash(
    useSystemColor,
    seedColorValue,
    oledBlack,
    hasBackgroundImage,
  );
}

/// 把 `DynamicColorBuilder` 的取色结果往下传。阅读页要单独构建一套亮/暗主题，
/// 拿不到它就会丢掉动态取色。
class AppDynamicSchemes extends InheritedWidget {
  const AppDynamicSchemes({
    super.key,
    required this.light,
    required this.dark,
    required super.child,
  });

  final ColorScheme? light;
  final ColorScheme? dark;

  static AppDynamicSchemes? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppDynamicSchemes>();

  ColorScheme? forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  @override
  bool updateShouldNotify(AppDynamicSchemes oldWidget) =>
      light != oldWidget.light || dark != oldWidget.dark;
}

/// 按输入缓存主题实例。新建 `ThemeData` 会让 `AnimatedTheme` 判定主题变更，标脏所有
/// `Theme.of` 依赖者（含 indexedStack 里的离屏 tab），实测一次导航多 30~43ms。
typedef _ThemeKey = (Brightness, AppPalette, ColorScheme?);

final Map<_ThemeKey, ThemeData> _themeCache = <_ThemeKey, ThemeData>{};

ThemeData buildAppTheme({
  required Brightness brightness,
  required AppSettings settings,
  ColorScheme? dynamicScheme,
}) => buildAppThemeFor(
  brightness: brightness,
  palette: AppPalette.of(settings),
  dynamicScheme: dynamicScheme,
);

ThemeData buildAppThemeFor({
  required Brightness brightness,
  required AppPalette palette,
  ColorScheme? dynamicScheme,
}) {
  final _ThemeKey key = (brightness, palette, dynamicScheme);
  final ThemeData? cached = _themeCache[key];
  if (cached != null) return cached;
  // 配色改动会不断产生新键，超过上限就整体清空。
  if (_themeCache.length >= 8) _themeCache.clear();
  return _themeCache[key] = _buildAppTheme(
    brightness: brightness,
    palette: palette,
    dynamicScheme: dynamicScheme,
  );
}

ThemeData _buildAppTheme({
  required Brightness brightness,
  required AppPalette palette,
  ColorScheme? dynamicScheme,
}) {
  final useDynamic = palette.useSystemColor && dynamicScheme != null;
  var scheme = useDynamic
      ? dynamicScheme.copyWith(brightness: brightness)
      : ColorScheme.fromSeed(
          seedColor: parseSeedColor(palette.seedColorValue),
          brightness: brightness,
        );

  final isOledDark = brightness == Brightness.dark && palette.oledBlack;
  if (isOledDark) {
    scheme = scheme.copyWith(
      surface: OledPalette.surface,
      surfaceContainer: OledPalette.card,
      surfaceContainerLow: OledPalette.card,
      surfaceContainerHighest: OledPalette.surfaceContainerHighest,
      onSurface: OledPalette.label,
      onSurfaceVariant: OledPalette.secondaryLabel,
      outlineVariant: OledPalette.separator,
    );
  }

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: palette.hasBackgroundImage
        ? Colors.transparent
        : isOledDark
        ? OledPalette.background
        : scheme.surface,
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: palette.hasBackgroundImage
          ? scheme.surface.withValues(alpha: 0.88)
          : isOledDark
          ? OledPalette.background
          : scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: isOledDark ? 0 : 3,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.hasBackgroundImage
          ? scheme.surface.withValues(alpha: 0.9)
          : isOledDark
          ? OledPalette.background
          : scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      elevation: 3,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: isOledDark ? OledPalette.background : scheme.surface,
      indicatorColor: scheme.secondaryContainer,
      labelType: NavigationRailLabelType.all,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      space: 1,
      thickness: 1,
    ),
    cardTheme: CardThemeData(
      color: palette.hasBackgroundImage
          ? scheme.surfaceContainer.withValues(alpha: 0.9)
          : scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: base.textTheme.bodyLarge?.copyWith(
        color: scheme.onSurface,
      ),
      subtitleTextStyle: base.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      iconColor: scheme.primary,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isOledDark
          ? OledPalette.card
          : scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
    ),
    // Transparent pages share the persistent application background. Use a
    // two-phase fade so outgoing and incoming page contents are never painted
    // together over that background.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: _BackgroundSafePageTransitionsBuilder(),
        TargetPlatform.iOS: _BackgroundSafePageTransitionsBuilder(),
        TargetPlatform.linux: _BackgroundSafePageTransitionsBuilder(),
        TargetPlatform.macOS: _BackgroundSafePageTransitionsBuilder(),
        TargetPlatform.windows: _BackgroundSafePageTransitionsBuilder(),
        TargetPlatform.fuchsia: _BackgroundSafePageTransitionsBuilder(),
      },
    ),
  );
}

class _BackgroundSafePageTransitionsBuilder extends PageTransitionsBuilder {
  const _BackgroundSafePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final incoming = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.5, 1, curve: Curves.easeOut),
      reverseCurve: const Interval(0.5, 1, curve: Curves.easeIn),
    );
    final outgoing = ReverseAnimation(
      CurvedAnimation(
        parent: secondaryAnimation,
        curve: const Interval(0, 0.5, curve: Curves.easeIn),
        reverseCurve: const Interval(0, 0.5, curve: Curves.easeOut),
      ),
    );
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[incoming, outgoing]),
      child: child,
      builder: (_, child) => Opacity(
        opacity: (incoming.value * outgoing.value).clamp(0.0, 1.0).toDouble(),
        child: child,
      ),
    );
  }
}
