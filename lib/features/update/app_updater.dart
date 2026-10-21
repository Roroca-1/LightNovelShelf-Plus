import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../../core/platform/android_app_installer.dart';
import '../../data/app_update.dart';
import '../../data/providers.dart';
import '../../data/settings/app_settings.dart';
import '../../shared/widgets/app_dialogs.dart';
import '../../shared/widgets/html_content.dart';

final Provider<AppUpdater> appUpdaterProvider = Provider<AppUpdater>((ref) {
  final runtime = ref.watch(appRuntimeProvider);
  return AppUpdater(
    repository: AppUpdateRepository(store: runtime.keyValueStore),
    settings: runtime.settings,
  );
});

/// Android 下载安装包并安装；iOS 与桌面（Linux/Windows/macOS）跳到 Release 页。
bool get appUpdateSupported => !kIsWeb;

enum _ReleaseAction { confirm, later, ignore }

class _ApkDownload {
  const _ApkDownload({
    required this.version,
    required this.progress,
    required this.file,
  });

  final String version;
  final ValueNotifier<double?> progress;
  final Future<File> file;
}

/// Android 新版本自动下载后提示安装，iOS 只提示前往下载页。
class AppUpdater {
  AppUpdater({
    required AppUpdateRepository repository,
    required SettingsController settings,
  }) : _repository = repository,
       _settings = settings;

  final AppUpdateRepository _repository;
  final SettingsController _settings;
  _ApkDownload? _download;
  bool _prompting = false;
  bool _manualChecking = false;
  bool _manualDownloading = false;
  Future<void>? _cleanup;
  Future<void> _downloadTail = Future<void>.value();

  /// 启动后调用一次，失败只记日志。
  Future<void> checkOnLaunch() async {
    if (!appUpdateSupported || !_settings.settings.autoCheckUpdate) return;
    try {
      final release = await _fetchNewer();
      if (release == null) return;
      if (await _repository.ignoredVersion() == release.version) return;
      // iOS/桌面没有应用内安装流程；Android 缺少可校验的安装包（没有 digest、
      // 没有本机架构）时同样只能打开 Release 页，绝不装来源不明的包。
      if (!Platform.isAndroid || await _installableAsset(release) == null) {
        await _prompt(release, null, allowIgnore: true);
        return;
      }
      final file = await _startDownload(release).file;
      if (!_manualDownloading) {
        await _prompt(release, file, allowIgnore: true);
      }
    } catch (error) {
      debugPrint('自动检查更新失败：$error');
    }
  }

  /// 「检查更新」入口：忽略过的版本也会提示，失败要告诉用户。
  Future<void> checkManually(BuildContext context) async {
    if (_manualChecking) return;
    _manualChecking = true;
    try {
      await _checkManually(context);
    } finally {
      _manualChecking = false;
      _manualDownloading = false;
    }
  }

  Future<void> _checkManually(BuildContext context) async {
    final AppRelease? release;
    try {
      release = await _fetchNewer();
    } catch (error) {
      if (context.mounted) {
        await showAppAlert(
          context: context,
          title: '检查更新失败',
          message: '$error',
        );
      }
      return;
    }
    if (!context.mounted) return;
    if (release == null) {
      showAppSnackBar(context, '已是最新版本');
      return;
    }
    if (!Platform.isAndroid || await _installableAsset(release) == null) {
      await _prompt(release, null, allowIgnore: false);
      return;
    }
    if (!context.mounted) return;

    _manualDownloading = true;
    final download = _startDownload(release);
    final result = download.file.then<(File?, Object?)>(
      (file) => (file, null),
      onError: (Object error) => (null, error),
    );
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _DownloadProgressDialog(release: release!, download: download),
    );
    final (file, error) = await result;
    if (error != null) {
      await _alert('下载更新失败', '$error');
      return;
    }
    await _prompt(release, file!, allowIgnore: false);
  }

  Future<void> _alert(String title, String message) async {
    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await showAppAlert(context: context, title: title, message: message);
  }

  Future<AppRelease?> _fetchNewer() async {
    final release = await _repository.fetchLatest();
    final current = await _currentVersion();
    if (Platform.isAndroid) {
      await (_cleanup ??= _repository.cleanInstalledApks(current));
    }
    return isNewerVersion(release.version, current) ? release : null;
  }

  /// 已安装版本；`PackageInfo` 在个别平台上读不到时退回构建注入的发布标签。
  Future<String> _currentVersion() async {
    var packageVersion = '';
    try {
      packageVersion = (await PackageInfo.fromPlatform()).version;
    } catch (error) {
      debugPrint('读取应用版本失败：$error');
    }
    return resolveCurrentVersion(packageVersion, compiledReleaseTag);
  }

  /// Android 只有带 sha256 的同架构安装包才会自动下载安装。
  Future<AppReleaseAsset?> _installableAsset(AppRelease release) async =>
      release.installableApkFor(await AndroidAppInstaller.supportedAbis());

  /// 同一版本只下载一次，自动检查与手动检查共用进行中的下载。
  _ApkDownload _startDownload(AppRelease release) {
    final existing = _download;
    if (existing != null && existing.version == release.version) {
      return existing;
    }
    final progress = ValueNotifier<double?>(null);
    late final _ApkDownload download;
    download = _ApkDownload(
      version: release.version,
      progress: progress,
      file: _downloadTail
          .then((_) => _downloadApk(release, progress))
          // 失败时清掉，下次检查重新下载；成功的保留给手动检查复用。
          .catchError((Object error, StackTrace stackTrace) {
            if (identical(_download, download)) _download = null;
            Error.throwWithStackTrace(error, stackTrace);
          }),
    );
    _download = download;
    _downloadTail = download.file.then<void>((_) {}, onError: (Object _) {});
    return download;
  }

  Future<File> _downloadApk(
    AppRelease release,
    ValueNotifier<double?> progress,
  ) async {
    final asset = await _installableAsset(release);
    if (asset == null) {
      throw const AppUpdateException('新版本没有可校验的安装包，请前往 Release 页下载。');
    }
    return _repository.downloadApk(
      release,
      asset,
      onProgress: (received, total) =>
          progress.value = total > 0 ? received / total : null,
    );
  }

  Future<void> _prompt(
    AppRelease release,
    File? apk, {
    required bool allowIgnore,
  }) async {
    if (_prompting) return;
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    _prompting = true;
    try {
      final action = await showDialog<_ReleaseAction>(
        context: context,
        builder: (_) => _ReleaseDialog(
          release: release,
          confirmLabel: apk == null ? '前往下载' : '立即安装',
          allowIgnore: allowIgnore,
        ),
      );
      switch (action) {
        case _ReleaseAction.confirm:
          if (apk == null) {
            await launchUrl(
              release.pageUrl,
              mode: LaunchMode.externalApplication,
            );
          } else {
            await _install(apk);
          }
        case _ReleaseAction.ignore:
          await _repository.ignoreVersion(release.version);
        case _ReleaseAction.later || null:
          break;
      }
    } finally {
      _prompting = false;
    }
  }

  Future<void> _install(File apk) async {
    try {
      if (!await AndroidAppInstaller.requestInstallPermission()) {
        await _alert('无法安装更新', '请在系统设置中允许「轻书架」安装未知应用后重试。');
        return;
      }
      await AndroidAppInstaller.install(apk.path);
    } catch (error) {
      await _alert('无法安装更新', '$error');
    }
  }
}

class _DownloadProgressDialog extends StatefulWidget {
  const _DownloadProgressDialog({
    required this.release,
    required this.download,
  });

  final AppRelease release;
  final _ApkDownload download;

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  @override
  void initState() {
    super.initState();
    // 成功或失败都关掉进度框，由调用方接着提示安装或报错。
    widget.download.file.then<void>(
      (_) => _close(),
      onError: (Object _) => _close(),
    );
  }

  void _close() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('正在下载 v${widget.release.version}'),
    content: ValueListenableBuilder<double?>(
      valueListenable: widget.download.progress,
      builder: (context, progress, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 12),
          Text(
            progress == null ? '准备中…' : '${(progress * 100).floor()}%',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('后台下载'),
      ),
    ],
  );
}

class _ReleaseDialog extends StatelessWidget {
  const _ReleaseDialog({
    required this.release,
    required this.confirmLabel,
    required this.allowIgnore,
  });

  final AppRelease release;
  final String confirmLabel;
  final bool allowIgnore;

  @override
  Widget build(BuildContext context) {
    final notes = release.notes;
    return AlertDialog(
      title: Text('发现新版本 v${release.version}'),
      content: notes.isEmpty
          ? null
          : ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.5,
              ),
              child: SingleChildScrollView(
                child: HtmlContent(
                  html: md.markdownToHtml(
                    notes.replaceAll('<', '&lt;'),
                    extensionSet: md.ExtensionSet.gitHubFlavored,
                    encodeHtml: true,
                  ),
                ),
              ),
            ),
      actions: <Widget>[
        if (allowIgnore)
          TextButton(
            onPressed: () => Navigator.of(context).pop(_ReleaseAction.ignore),
            child: const Text('忽略此版本'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_ReleaseAction.later),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ReleaseAction.confirm),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
