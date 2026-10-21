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
    final pageUrl = Uri.tryParse(page);
    if (pageUrl == null) {
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
        final parsedUrl = Uri.tryParse(url);
        if (parsedUrl == null) continue;
        final digest = asset['digest'];
        assets.add(
          AppReleaseAsset(
            name: name,
            url: parsedUrl,
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
      version: releaseVersion(tag),
      notes: notes is String ? notes.trim() : '',
      pageUrl: pageUrl,
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

/// `-Plus` 后面紧跟的重发序号：`V1.13.2-Plus.1` → 1，`V1.13.2-Plus` → 0。
///
/// 同一个上游版本在 Plus 侧重发补丁时只改这个序号，所以它必须参与比较，
/// 否则 `V1.13.2-Plus.1` 会被当成与 `1.13.2` 相等而永远不提示更新。
int plusRevision(String tag) =>
    int.tryParse(
      RegExp(r'[-+]plus\.(\d+)', caseSensitive: false).firstMatch(tag)?.group(1) ??
          '',
    ) ??
    0;

/// 版本身份：同一上游版本在 Plus 侧重发时靠 `-Plus.N` 区分。
///
/// 只用于忽略记录与下载文件名，保证「忽略 `1.13.2` 之后 `1.13.2-Plus.1` 仍会提示」；
/// 展示与比较仍走 [normalizeVersionTag]。
String releaseVersion(String tag) {
  final base = normalizeVersionTag(tag);
  final revision = plusRevision(tag);
  return revision == 0 ? base : '$base-Plus.$revision';
}

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

/// 逐段比较数字：`主.次.修订` + `-Plus.N` 重发序号，忽略 `+构建号`。
///
/// `V1.13.2-Plus` 与 `1.13.2` 判等（序号 0），`V1.13.2-Plus.1` 比它们新。
bool isNewerVersion(String candidate, String current) {
  List<int> parse(String version) {
    final segments = normalizeVersionTag(version)
        .split('+')
        .first
        .split('.')
        .map((part) => int.tryParse(part.trim()) ?? 0)
        .toList();
    segments.add(plusRevision(version));
    return segments;
  }
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
  AppUpdateRepository({
    required KeyValueStore store,
    http.Client? client,
    Directory? updatesDirectory,
  }) : _store = store,
       _client = client ?? http.Client(),
       _overrideDirectory = updatesDirectory;

  final KeyValueStore _store;
  final http.Client _client;

  /// 测试注入的目录；正式运行时用系统临时目录下的 `updates/`。
  final Directory? _overrideDirectory;

  Future<Directory> _updates() async =>
      _overrideDirectory ??
      Directory('${(await getTemporaryDirectory()).path}/updates');

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
    final Object? payload;
    try {
      payload = jsonDecode(utf8.decode(response.bodyBytes));
    } on Exception {
      throw const AppUpdateException('版本信息格式错误。');
    }
    return AppRelease.decode(payload);
  }

  Future<String?> ignoredVersion() => _store.read(_ignoredVersionKey);

  Future<void> ignoreVersion(String version) =>
      _store.write(_ignoredVersionKey, version);

  /// 只保留当前版本对应的下载文件，其余 `.apk` / `.part` 全部清掉。
  ///
  /// 下载文件名为 `<version>-<asset.name>`，按版本前缀判断即可；目录不存在时直接返回，
  /// 重复调用保持幂等（已删掉的文件不会再次报错）。
  Future<void> cleanInstalledApks(String currentVersion) async {
    final directory = await _updates();
    if (!await directory.exists()) return;
    final keep = normalizeVersionTag(currentVersion);
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith('.apk') && !name.endsWith('.part')) continue;
      if (keep.isNotEmpty && (name == keep || name.startsWith('$keep-'))) {
        continue;
      }
      try {
        await entity.delete();
      } on FileSystemException {
        // 别的流程已经删掉时保持幂等。
      }
    }
  }

  /// 下载到临时目录的 `updates/`，同版本已下载且校验通过时直接复用。
  Future<File> downloadApk(
    AppRelease release,
    AppReleaseAsset asset, {
    void Function(int received, int total)? onProgress,
  }) async {
    final directory = await _updates();
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
      await sink.close();
    } on TimeoutException {
      await _discard(part, sink);
      throw const AppUpdateException('下载安装包超时。');
    } on Exception {
      await _discard(part, sink);
      throw const AppUpdateException('下载安装包中断。');
    }
    hasher.close();
    final checksum = digest.value;
    if (checksum == null || !_matches(received, checksum, asset)) {
      await _discard(part, sink);
      throw const AppUpdateException('安装包校验失败。');
    }
    return part.rename(target.path);
  }

  /// 关掉写入句柄后再删临时文件，避免半成品 `.part` 堆积（Windows 上开着句柄删不掉）。
  static Future<void> _discard(File part, IOSink sink) async {
    try {
      await sink.close();
    } on Exception {
      // 已经关闭过时忽略。
    }
    try {
      if (await part.exists()) await part.delete();
    } on FileSystemException {
      // 删不掉也不影响上层已经确定的异常。
    }
  }

  static bool _matches(int length, Digest digest, AppReleaseAsset asset) =>
      length == asset.size &&
      (asset.sha256 == null || digest.toString() == asset.sha256);
}
