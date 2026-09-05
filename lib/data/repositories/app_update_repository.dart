import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

const String _releaseApi =
    'https://api.github.com/repos/Roroca-1/LightNovelShelf-Plus/releases/latest';
const String compiledReleaseTag = String.fromEnvironment('APP_RELEASE_TAG');

class AppUpdate {
  const AppUpdate({
    required this.tag,
    required this.notes,
    required this.downloadUrl,
    required this.releaseUrl,
  });

  final String tag;
  final String notes;
  final String? downloadUrl;
  final String releaseUrl;
}

class AppUpdateRepository {
  const AppUpdateRepository();

  Future<AppUpdate?> check() async {
    final response = await http
        .get(
          Uri.parse(_releaseApi),
          headers: const <String, String>{
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final tag = (data['tag_name'] as String? ?? '').trim();
    if (tag.isEmpty || !await _isNewer(tag)) return null;
    final assets = (data['assets'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>();
    String? downloadUrl;
    for (final asset in assets) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      final matches = Platform.isAndroid
          ? name.endsWith('arm64-v8a.apk')
          : Platform.isWindows
          ? name.endsWith('setup.exe')
          : Platform.isLinux
          ? (Platform.environment['APPIMAGE']?.isNotEmpty == true
                ? name.endsWith('.appimage')
                : name.endsWith('.deb'))
          : false;
      if (matches) {
        downloadUrl = asset['browser_download_url'] as String?;
        break;
      }
    }
    return AppUpdate(
      tag: tag,
      notes: data['body'] as String? ?? '',
      downloadUrl: downloadUrl,
      releaseUrl: data['html_url'] as String? ??
          'https://github.com/Roroca-1/LightNovelShelf-Plus/releases/latest',
    );
  }

  Future<bool> _isNewer(String latest) async {
    var current = compiledReleaseTag.trim();
    if (current.isEmpty) current = (await PackageInfo.fromPlatform()).version;
    final a = _numbers(latest);
    final b = _numbers(current);
    final length = a.length > b.length ? a.length : b.length;
    for (var index = 0; index < length; index++) {
      final left = index < a.length ? a[index] : 0;
      final right = index < b.length ? b[index] : 0;
      if (left != right) return left > right;
    }
    return false;
  }

  List<int> _numbers(String value) => RegExp(
    r'\d+',
  ).allMatches(value).map((match) => int.parse(match.group(0)!)).toList();
}
