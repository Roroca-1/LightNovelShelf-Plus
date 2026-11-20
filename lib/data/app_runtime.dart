import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/network/request_scheduler.dart';
import '../core/network/signalr_connection.dart';
import '../core/feature_flags.dart';
import '../core/platform/cache_file_store.dart';
import '../core/platform/stores.dart';
import 'api/api_client.dart';
import 'api/endpoints.dart';
import 'session/auth_controller.dart';
import 'session/visitor_id.dart';
import 'settings/app_settings.dart';
import 'repositories/user_font_repository.dart';

/// 应用启动时一次性构建的运行时依赖。
class AppRuntime {
  AppRuntime({
    required this.credentials,
    required this.keyValueStore,
    KeyValueStore? cacheStore,
    required this.settings,
    required this.signalR,
    required this.api,
    required this.auth,
    required this.hasStoredSession,
  }) : cacheStore = cacheStore ?? keyValueStore;

  final CredentialStore credentials;
  final KeyValueStore keyValueStore;
  final KeyValueStore cacheStore;
  final SettingsController settings;
  final SignalRConnection signalR;
  final ApiClient api;
  final AuthController auth;
  final bool hasStoredSession;

  static Future<T> _startupStep<T>(
    String name,
    Future<T> Function() operation,
  ) async {
    try {
      return await operation().timeout(const Duration(seconds: 6));
    } on TimeoutException {
      throw StateError('$name 超时。');
    } catch (error) {
      throw StateError('$name 失败：$error');
    }
  }

  static Future<AppRuntime> bootstrap() async {
    CredentialStore credentials = SecureCredentialStore();

    // 偏好存储、UA 与安全凭据互不依赖，并行初始化缩短冷启动时间。
    final keyValueFuture = _startupStep(
      '本地偏好设置初始化',
      PreferencesKeyValueStore.open,
    );
    final userAgentFuture = _backendUserAgent();
    final refreshTokenFuture = credentials
        .read(AuthCredentialKeys.refreshToken)
        .timeout(const Duration(seconds: 6));

    final keyValueStore = await keyValueFuture;
    final settingsFuture = _startupStep(
      '应用设置读取',
      () => SettingsController.load(keyValueStore),
    );

    String? refreshToken;
    try {
      refreshToken = await refreshTokenFuture;
    } catch (error) {
      // -34018 是未签名 / TrollStore 安装包缺少 Keychain entitlement 的系统错误。
      // 仅 iOS 在这个明确场景降级，其他平台或其他错误不能静默丢弃。
      if (defaultTargetPlatform != TargetPlatform.iOS ||
          !error.toString().contains('-34018')) {
        rethrow;
      }
      debugPrint(
        'iOS Keychain entitlement unavailable; using app-local credentials.',
      );
      credentials = KeyValueCredentialStore(keyValueStore);
      refreshToken = await _startupStep(
        '安全凭据读取',
        () => credentials.read(AuthCredentialKeys.refreshToken),
      );
    }

    final settings = await settingsFuture;
    final customFontPath = settings.settings.customReaderFontPath;
    if (enableReaderFonts && customFontPath != null) {
      // 自定义阅读字体只在进入阅读页时用到，放到后台加载，不阻塞首屏。
      unawaited(
        UserFontRepository.instance
            .load(customFontPath)
            .then((_) {}, onError: (_) {}),
      );
    }
    final scheduler = RateLimitRequestScheduler();
    final apiOrigin = settings.settings.apiServer.apiOrigin;
    final userAgent = await userAgentFuture;
    final visitor = VisitorId(credentials: credentials);

    Future<Map<String, String>> backendHeaders() async => <String, String>{
      'User-Agent': userAgent,
      'x-id': await visitor.value(),
    };

    final signalR = SignalRConnection(
      endpoint: ServiceEndpoints.signalRHubFor(apiOrigin),
      accessTokenFactory: () =>
          credentials.read(AuthCredentialKeys.sessionToken),
      headersFactory: backendHeaders,
    );

    final api = ApiClient(
      apiOrigin: apiOrigin,
      signalR: signalR,
      scheduler: scheduler,
      headers: () async {
        final token = await credentials.read(AuthCredentialKeys.sessionToken);
        return <String, String>{
          ...await backendHeaders(),
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        };
      },
    );

    final auth = AuthController(
      api: api,
      credentials: credentials,
      signalR: signalR,
    );
    api.authRetry = auth.refresh;

    return AppRuntime(
      credentials: credentials,
      keyValueStore: keyValueStore,
      cacheStore: FileCacheStore(legacy: keyValueStore),
      settings: settings,
      signalR: signalR,
      api: api,
      auth: auth,
      hasStoredSession: refreshToken != null && refreshToken.isNotEmpty,
    );
  }

  /// 恢复会话并建立实时连接；失败时降级为未登录。
  Future<void> start() async {
    try {
      final restored = await auth.bootstrap();
      if (restored) await signalR.connect();
    } catch (error) {
      debugPrint('会话初始化失败：$error');
    }
  }

  Future<void> dispose() async {
    api.close();
    await signalR.dispose();
  }
}

/// HTTP 头只允许 ASCII，固定用英文标识加版本号。
Future<String> _backendUserAgent() async {
  const String name = 'LightNovelShelf-Plus';
  try {
    final info = await PackageInfo.fromPlatform();
    return info.version.isEmpty ? name : '$name/${info.version}';
  } catch (_) {
    return name;
  }
}
