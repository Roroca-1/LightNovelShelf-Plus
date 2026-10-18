import 'package:flutter/services.dart';

const MethodChannel _appUpdateChannel = MethodChannel(
  'app.lightnovel.shelf/app_update',
);

/// Android 应用内更新的原生入口，只在 Android 上调用。
abstract final class AndroidAppInstaller {
  /// 设备支持的 ABI，首选的排在前面。
  static Future<List<String>> supportedAbis() async =>
      await _appUpdateChannel.invokeListMethod<String>('supportedAbis') ??
      const <String>[];

  /// 未授权安装未知应用时会跳到系统设置页，返回用户回来后的授权状态。
  static Future<bool> requestInstallPermission() async =>
      await _appUpdateChannel.invokeMethod<bool>('requestInstallPermission') ??
      false;

  /// 安装包必须位于临时目录的 `updates/` 下，FileProvider 只暴露这个目录。
  static Future<void> install(String path) =>
      _appUpdateChannel.invokeMethod<void>('install', path);
}
