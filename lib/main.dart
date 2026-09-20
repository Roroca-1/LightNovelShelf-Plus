import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/router.dart';
import 'app/theme/app_theme.dart';
import 'core/platform/app_system_ui.dart';
import 'core/platform/desktop_platform.dart';
import 'data/app_runtime.dart';
import 'data/providers.dart';
import 'data/retry_policy.dart';
import 'data/session/auth_controller.dart';
import 'data/settings/app_settings.dart';
import 'shared/widgets/background_image_layer.dart';

/// 开发期通过 `--dart-define=REFRESH_TOKEN=...` 注入的刷新令牌，用于跳过手动登录。
const String _injectedRefreshToken = String.fromEnvironment('REFRESH_TOKEN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _AppBootstrap());
}

/// 先交出 Flutter 首帧，再进行可能受系统存储影响的启动初始化。
class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  late Future<AppRuntime> _runtime;

  @override
  void initState() {
    super.initState();
    _runtime = _bootstrap();
  }

  Future<AppRuntime> _bootstrap() async {
    await AppSystemUi.restoreDefault(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
    await initializeDateFormatting('zh_CN');
    final runtime = await AppRuntime.bootstrap().timeout(
      const Duration(seconds: 12),
      onTimeout: () => throw TimeoutException('本地存储初始化超时。'),
    );
    if (_injectedRefreshToken.isNotEmpty) {
      await runtime.credentials.write(
        AuthCredentialKeys.refreshToken,
        _injectedRefreshToken,
      );
    }
    unawaited(runtime.start());
    return runtime;
  }

  void _retry() => setState(() => _runtime = _bootstrap());

  @override
  Widget build(BuildContext context) => FutureBuilder<AppRuntime>(
    future: _runtime,
    builder: (context, snapshot) {
      final runtime = snapshot.data;
      if (runtime != null) {
        return ProviderScope(
          retry: apiRetry,
          overrides: <Override>[appRuntimeProvider.overrideWithValue(runtime)],
          child: const LightNovelShelfApp(),
        );
      }
      return _StartupScreen(failure: snapshot.hasError, onRetry: _retry);
    },
  );
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen({required this.failure, required this.onRetry});

  final bool failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
    ),
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: failure
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.error_outline, size: 44),
                    const SizedBox(height: 16),
                    const Text('应用启动失败'),
                    const SizedBox(height: 8),
                    const Text('本地存储初始化没有完成，请重试。', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: onRetry, child: const Text('重试')),
                  ],
                )
              : const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在启动轻书架Plus…'),
                  ],
                ),
        ),
      ),
    ),
  );
}

class LightNovelShelfApp extends ConsumerWidget {
  const LightNovelShelfApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 根节点只订阅主题与语言相关字段，字号、阅读器排版之类的写入不再重建
    // MaterialApp.router → Router → Navigator。
    final palette = ref.watch(appSettingsProvider.select(AppPalette.of));
    final theme = ref.watch(
      appSettingsProvider.select((settings) => settings.theme),
    );
    final language = ref.watch(
      appSettingsProvider.select((settings) => settings.language),
    );
    final appBackground = ref.watch(
      appSettingsProvider.select((settings) => settings.appBackground),
    );
    final router = ref.watch(routerProvider);
    // 亮暗由 `themeMode` 决定，两套主题都要构建。

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return AppDynamicSchemes(
          light: lightDynamic,
          dark: darkDynamic,
          child: MaterialApp.router(
            title: '轻书架Plus',
            debugShowCheckedModeBanner: false,
            builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
              value: AppSystemUi.defaultOverlayStyle(
                Theme.of(context).brightness,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ColoredBox(color: Theme.of(context).colorScheme.surface),
                  BackgroundImageLayer(
                    path: appBackground.path,
                    blur: appBackground.blur,
                    brightness: appBackground.brightness,
                  ),
                  if (child != null)
                    CallbackShortcuts(
                      bindings: isDesktopPlatform
                          ? <ShortcutActivator, VoidCallback>{
                              const SingleActivator(
                                LogicalKeyboardKey.escape,
                              ): () {
                                rootNavigatorKey.currentState?.maybePop();
                              },
                            }
                          : const <ShortcutActivator, VoidCallback>{},
                      child: Focus(
                        autofocus: true,
                        child: switch (defaultTargetPlatform) {
                          TargetPlatform.linux || TargetPlatform.windows =>
                            MediaQuery.withClampedTextScaling(
                              minScaleFactor: 1.08,
                              maxScaleFactor: 1.6,
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 1600,
                                  ),
                                  child: child,
                                ),
                              ),
                            ),
                          _ => child,
                        },
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ),
            routerConfig: router,
            theme: buildAppThemeFor(
              brightness: Brightness.light,
              palette: palette,
              dynamicScheme: lightDynamic,
            ),
            darkTheme: buildAppThemeFor(
              brightness: Brightness.dark,
              palette: palette,
              dynamicScheme: darkDynamic,
            ),
            themeMode: switch (theme) {
              ThemeSetting.light => ThemeMode.light,
              ThemeSetting.dark => ThemeMode.dark,
              ThemeSetting.system => ThemeMode.system,
            },
            locale: switch (language) {
              LanguageSetting.zhCN => const Locale('zh', 'CN'),
              LanguageSetting.zhTW => const Locale('zh', 'TW'),
              LanguageSetting.system => null,
            },
            supportedLocales: const <Locale>[
              Locale('zh', 'CN'),
              Locale('zh', 'TW'),
            ],
            localizationsDelegates: const <LocalizationsDelegate<Object?>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          ),
        );
      },
    );
  }
}
