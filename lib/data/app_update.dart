import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/platform/stores.dart';

/// Plus 自己的发布源；「关于」页的 GitHub 链接同样指向这里。
const String _latestReleaseUrl =
    'https://api.github.com/repos/Roroca-1/LightNovelShelf-Plus/releases/latest';

/// 构建时注入的发布标签（CI 走 `--dart-define=APP_RELEASE_TAG=...`），
/// 只在 `PackageInfo` 读不到版本时兜底比较。
const String compiledReleaseTag = String.fromEnvironment('APP_RELEASE_TAG');

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
      version: normalizeVersionTag(tag),
      notes: notes is String ? notes.trim() : '',
      pageUrl: Uri.parse(page),
      assets: assets,
    );
  }

  /// 按设备 ABI 偏好挑安装包；分 ABI 构建的 versionCode 带 ABI 前缀，装错架构会被当成降级。
  ///
  /// Plus 的产物名是 `LightNovelShelfPlus-<ARTIFACT_TAG>-arm64-v8a.apk`，这里只按
  /// `-<abi>.apk` 后缀匹配，桌面端的 AppImage/deb/pkg/Setup/ipa 不会误中。
  AppReleaseAsset? androidApkFor(List<String> abis) {
    for (final abi in abis) {
      final suffix = '-${abi.toLowerCase()}.apk';
      for (final asset in assets) {
        if (asset.name.toLowerCase().endsWith(suffix)) return asset;
      }
    }
    return null;
  }

  /// 自动安装要求资产带 sha256：Plus 早期的 Release 没有 `digest` 字段，
  /// 校验不了就不下载安装，返回 null 让调用方降级成打开 Release 页。
  AppReleaseAsset? installableApkFor(List<String> abis) {
    final asset = androidApkFor(abis);
    return asset == null || asset.sha256 == null ? null : asset;
  }
}

/// 归一化 Plus 的发布标签：去掉前导 `v/V`，再截断到第一个 `-`。
///
/// `V1.13.2-Plus`、`V1.12.3-Plus.1`、`v1.13.2` 都得到 `主.次.修订`；
/// 上游只摘小写 v 的写法会留下 `-Plus` 后缀，版本比较随之出错。
String normalizeVersionTag(String tag) {
  var value = tag.trim();
  if (value.startsWith('v') || value.startsWith('V')) {
    value = value.substring(1);
  }
  final dash = value.indexOf('-');
  if (dash >= 0) value = value.substring(0, dash);
  return value.trim();
}

bool _hasDigit(String value) => RegExp(r'\d').hasMatch(value);

/// 当前版本：安装包信息优先（与 pubspec 的 `version:` 一致），
/// 读不到时退回构建注入的 `APP_RELEASE_TAG`；都没有就当 `0.0.0`。
String resolveCurrentVersion(String packageVersion, String compiledTag) {
  final fromPackage = normalizeVersionTag(packageVersion);
  if (_hasDigit(fromPackage)) return fromPackage;
  final fromTag = normalizeVersionTag(compiledTag);
  if (_hasDigit(fromTag)) return fromTag;
  return '0.0.0';
}

/// 关于页展示的版本串，保留 Plus 标识：`1.13.2-Plus (26)`。
String plusVersionLabel(String version, String buildNumber) {
  final base = normalizeVersionTag(version);
  if (!_hasDigit(base)) return '版本未知';
  final build = buildNumber.trim();
  return build.isEmpty ? '$base-Plus' : '$base-Plus ($build)';
}

/// 只比较 `主.次.修订` 的数字段，忽略 `+构建号` 与预发布后缀。
bool isNewerVersion(String candidate, String current) {
  List<int> parse(String version) =>
      normalizeVersionTag(version)
          .split('+')
          .first
          .split('.')
          .map((part) => int.tryParse(part.trim()) ?? 0)
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
