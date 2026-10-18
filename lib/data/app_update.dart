import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/platform/stores.dart';

const String _latestReleaseUrl =
    'https://api.github.com/repos/LightNovelShelf/Flutter/releases/latest';
const String _ignoredVersionKey = 'app_update_ignored_version';
const Duration _requestTimeout = Duration(seconds: 15);
const Duration _downloadStallTimeout = Duration(seconds: 30);

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AppReleaseAsset {
  const AppReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
    required this.sha256,
  });

  final String name;
  final Uri url;
  final int size;

  /// GitHub 返回的 `digest` 去掉 `sha256:` 前缀；旧版本 Release 没有这个字段。
  final String? sha256;
}

class AppRelease {
  const AppRelease({
    required this.version,
    required this.notes,
    required this.pageUrl,
    required this.assets,
  });

  /// 去掉 `v` 前缀的版本号，与 `PackageInfo.version` 同格式。
  final String version;
  final String notes;
  final Uri pageUrl;
  final List<AppReleaseAsset> assets;

  static AppRelease decode(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const AppUpdateException('版本信息格式错误。');
    }
    final tag = value['tag_name'];
    final page = value['html_url'];
    if (tag is! String || tag.isEmpty || page is! String) {
      throw const AppUpdateException('版本信息格式错误。');
    }
    final assets = <AppReleaseAsset>[];
    final rawAssets = value['assets'];
    if (rawAssets is List) {
      for (final asset in rawAssets) {
        if (asset is! Map<String, dynamic>) continue;
        final name = asset['name'];
        final url = asset['browser_download_url'];
        final size = asset['size'];
        if (name is! String || url is! String || size is! int) continue;
        final digest = asset['digest'];
        assets.add(
          AppReleaseAsset(
            name: name,
            url: Uri.parse(url),
            size: size,
            sha256: digest is String && digest.startsWith('sha256:')
                ? digest.substring('sha256:'.length).toLowerCase()
                : null,
          ),
        );
      }
    }
    final notes = value['body'];
    return AppRelease(
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      notes: notes is String ? notes.trim() : '',
      pageUrl: Uri.parse(page),
      assets: assets,
    );
  }

  /// 按设备 ABI 偏好挑安装包；分 ABI 构建的 versionCode 带 ABI 前缀，装错架构会被当成降级。
  AppReleaseAsset? androidApkFor(List<String> abis) {
    for (final abi in abis) {
      for (final asset in assets) {
        if (asset.name == 'app-android-$abi.apk') return asset;
      }
    }
    return null;
  }
}

/// 只比较 `主.次.修订` 的数字段，忽略 `+构建号` 与预发布后缀。
bool isNewerVersion(String candidate, String current) {
  List<int> parse(String version) => version
      .split('+')
      .first
      .split('-')
      .first
      .split('.')
      .map((part) => int.tryParse(part) ?? 0)
      .toList();
  final a = parse(candidate);
  final b = parse(current);
  for (var i = 0; i < math.max(a.length, b.length); i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// 从 GitHub Release 获取新版本并下载 Android 安装包。
class AppUpdateRepository {
  AppUpdateRepository({required KeyValueStore store, http.Client? client})
    : _store = store,
      _client = client ?? http.Client();

  final KeyValueStore _store;
  final http.Client _client;

  Future<AppRelease> fetchLatest() async {
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse(_latestReleaseUrl),
            headers: const <String, String>{
              'Accept': 'application/vnd.github+json',
            },
          )
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw const AppUpdateException('连接 GitHub 超时。');
    } on Exception {
      throw const AppUpdateException('无法连接 GitHub。');
    }
    if (response.statusCode != HttpStatus.ok) {
      throw AppUpdateException('获取版本信息失败（HTTP ${response.statusCode}）。');
    }
    return AppRelease.decode(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  Future<String?> ignoredVersion() => _store.read(_ignoredVersionKey);

  Future<void> ignoreVersion(String version) =>
      _store.write(_ignoredVersionKey, version);

  /// 只清理已安装版本及更早的包，保留其它更新弹窗仍可能使用的文件。
  Future<void> cleanInstalledApks(String currentVersion) async {
    final directory = Directory(
      '${(await getTemporaryDirectory()).path}/updates',
    );
    if (!await directory.exists()) return;
    final namePattern = RegExp(r'^([0-9]+(?:\.[0-9]+)*)-app-android-');
    await for (final entity in directory.list()) {
      final match = namePattern.firstMatch(entity.uri.pathSegments.last);
      if (match != null && !isNewerVersion(match.group(1)!, currentVersion)) {
        await entity.delete(recursive: true);
      }
    }
  }

  /// 下载到临时目录的 `updates/`，同版本已下载且校验通过时直接复用。
  Future<File> downloadApk(
    AppRelease release,
    AppReleaseAsset asset, {
    void Function(int received, int total)? onProgress,
  }) async {
    final directory = Directory(
      '${(await getTemporaryDirectory()).path}/updates',
    );
    await directory.create(recursive: true);
    final target = File('${directory.path}/${release.version}-${asset.name}');
    if (await target.exists() &&
        _matches(
          await target.length(),
          await sha256.bind(target.openRead()).first,
          asset,
        )) {
      return target;
    }

    final http.StreamedResponse response;
    try {
      response = await _client
          .send(http.Request('GET', asset.url))
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw const AppUpdateException('下载安装包超时。');
    } on Exception {
      throw const AppUpdateException('无法下载安装包。');
    }
    if (response.statusCode != HttpStatus.ok) {
      throw AppUpdateException('下载安装包失败（HTTP ${response.statusCode}）。');
    }

    final total = response.contentLength ?? asset.size;
    final part = File('${target.path}.part');
    final sink = part.openWrite();
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(
        _downloadStallTimeout,
      )) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } on TimeoutException {
      throw const AppUpdateException('下载安装包超时。');
    } on Exception {
      throw const AppUpdateException('下载安装包中断。');
    } finally {
      await sink.close();
    }
    hasher.close();
    if (!_matches(received, digest.value!, asset)) {
      await part.delete();
      throw const AppUpdateException('安装包校验失败。');
    }
    return part.rename(target.path);
  }

  static bool _matches(int length, Digest digest, AppReleaseAsset asset) =>
      length == asset.size &&
      (asset.sha256 == null || digest.toString() == asset.sha256);
}
