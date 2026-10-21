import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lightnovel_shelf_plus/core/platform/stores.dart';
import 'package:lightnovel_shelf_plus/data/app_update.dart';

class _FakeStore implements KeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

const String _digest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

AppReleaseAsset _asset(String name, {String? sha256}) => AppReleaseAsset(
  name: name,
  url: Uri.parse('https://example.com/$name'),
  size: 1024,
  sha256: sha256,
);

AppRelease _release(List<AppReleaseAsset> assets) => AppRelease(
  version: '1.13.2',
  notes: '',
  pageUrl: Uri.parse(
    'https://github.com/Roroca-1/LightNovelShelf-Plus/releases',
  ),
  assets: assets,
);

void main() {
  group('normalizeVersionTag', () {
    test('去掉大写 V 前缀并截断 Plus 后缀', () {
      expect(normalizeVersionTag('V1.13.2-Plus'), '1.13.2');
      expect(normalizeVersionTag('V1.12.3-Plus.1'), '1.12.3');
    });

    test('兼容上游小写 v 与裸版本号', () {
      expect(normalizeVersionTag('v1.13.2'), '1.13.2');
      expect(normalizeVersionTag('1.13.2'), '1.13.2');
      expect(normalizeVersionTag('  V1.13.2-Plus  '), '1.13.2');
      expect(normalizeVersionTag(''), '');
    });
  });

  group('plusRevision', () {
    test('读出 -Plus 后的重发序号', () {
      expect(plusRevision('V1.13.2-Plus'), 0);
      expect(plusRevision('V1.13.2-Plus.1'), 1);
      expect(plusRevision('v1.12.3-plus.12'), 12);
      expect(plusRevision('v1.13.2'), 0);
      expect(plusRevision('1.13.2-PlusX'), 0);
    });
  });

  group('releaseVersion', () {
    test('重发包保留序号作为身份，首发仍是基础版本', () {
      expect(releaseVersion('V1.13.2-Plus'), '1.13.2');
      expect(releaseVersion('V1.13.2-Plus.1'), '1.13.2-Plus.1');
      expect(releaseVersion('v1.12.3'), '1.12.3');
    });
  });

  group('isNewerVersion', () {
    test('Plus 标签与纯版本号相等时不提示更新', () {
      expect(isNewerVersion('V1.13.2-Plus', '1.13.2'), isFalse);
      expect(isNewerVersion('V1.13.2-Plus', 'V1.13.2-Plus'), isFalse);
      expect(isNewerVersion('1.13.2', 'V1.13.2-Plus'), isFalse);
    });

    test('同一上游版本的重发包 -Plus.N 提示更新', () {
      expect(isNewerVersion('V1.13.2-Plus.1', '1.13.2'), isTrue);
      expect(isNewerVersion('V1.12.3-Plus.1', '1.12.3'), isTrue);
      expect(isNewerVersion('V1.13.2-Plus.1', 'V1.13.2-Plus'), isTrue);
      expect(isNewerVersion('V1.13.2-Plus.2', 'V1.13.2-Plus.1'), isTrue);
      expect(isNewerVersion('V1.13.2-Plus', 'V1.13.2-Plus.1'), isFalse);
      expect(isNewerVersion('V1.13.2-Plus.1', 'V1.13.2-Plus.1'), isFalse);
    });

    test('更高版本提示更新，更旧版本不提示', () {
      expect(isNewerVersion('V1.14.0-Plus', '1.13.2'), isTrue);
      expect(isNewerVersion('V1.13.3-Plus', '1.13.2'), isTrue);
      expect(isNewerVersion('V1.12.3-Plus', '1.13.2'), isFalse);
      expect(isNewerVersion('V1.13.1-Plus', '1.13.2'), isFalse);
    });

    test('忽略构建号与缺位段', () {
      expect(isNewerVersion('1.13.2', '1.13.2+26'), isFalse);
      expect(isNewerVersion('1.13', '1.13.0'), isFalse);
      expect(isNewerVersion('1.13.1', '1.13.0'), isTrue);
    });
  });

  group('resolveCurrentVersion', () {
    test('安装包版本优先于构建注入标签', () {
      expect(resolveCurrentVersion('1.13.2', 'V1.13.2-Plus'), '1.13.2');
      expect(resolveCurrentVersion('1.14.0', 'V1.13.2-Plus'), '1.14.0');
    });

    test('安装包版本缺失时退回构建注入标签', () {
      expect(resolveCurrentVersion('', 'V1.13.2-Plus'), '1.13.2');
      expect(resolveCurrentVersion('  ', 'v1.12.3-Plus.1'), '1.12.3');
    });

    test('两边都取不到版本时按 0.0.0 处理', () {
      expect(resolveCurrentVersion('', 'ci-42'), '0.0.0');
      expect(resolveCurrentVersion('', ''), '0.0.0');
    });
  });

  group('plusVersionLabel', () {
    test('带上 Plus 标识与构建号', () {
      expect(plusVersionLabel('1.13.2', '26'), '1.13.2-Plus (26)');
      expect(plusVersionLabel('V1.13.2-Plus', ''), '1.13.2-Plus');
      expect(plusVersionLabel('', ''), '版本未知');
    });
  });
  group('AppRelease.androidApkFor', () {
    test('匹配 Plus 命名的 arm64 安装包', () {
      final release = _release(<AppReleaseAsset>[
        _asset(
          'LightNovelShelfPlus-V1.13.2-Plus-arm64-v8a.apk',
          sha256: _digest,
        ),
        _asset('LightNovelShelfPlus-V1.13.2-Plus-x86_64.AppImage'),
        _asset('LightNovelShelfPlus-V1.13.2-Plus-x86_64.deb'),
        _asset('LightNovelShelfPlus-V1.13.2-Plus-ios-unsigned.ipa'),
      ]);
      expect(
        release.androidApkFor(<String>['arm64-v8a'])?.name,
        'LightNovelShelfPlus-V1.13.2-Plus-arm64-v8a.apk',
      );
    });

    test('桌面与 iOS 产物不会被当成 Android 安装包', () {
      final release = _release(<AppReleaseAsset>[
        _asset('LightNovelShelfPlus-V1.13.2-Plus-x86_64.AppImage'),
        _asset('LightNovelShelfPlus-V1.13.2-Plus-x86_64.pkg.tar.zst'),
        _asset('LightNovelShelfPlus-V1.13.2-Plus-x86_64-Setup.exe'),
        _asset('LightNovelShelfPlus-V1.13.2-Plus-ios-unsigned.ipa'),
      ]);
      expect(release.androidApkFor(<String>['x86_64', 'arm64-v8a']), isNull);
    });

    test('按设备 ABI 偏好顺序取第一个命中', () {
      final release = _release(<AppReleaseAsset>[
        _asset(
          'LightNovelShelfPlus-V1.13.2-Plus-arm64-v8a.apk',
          sha256: _digest,
        ),
        _asset(
          'LightNovelShelfPlus-V1.13.2-Plus-armeabi-v7a.apk',
          sha256: _digest,
        ),
      ]);
      expect(
        release.androidApkFor(<String>['armeabi-v7a', 'arm64-v8a'])?.name,
        'LightNovelShelfPlus-V1.13.2-Plus-armeabi-v7a.apk',
      );
    });

    test('没有本机架构的安装包时返回空', () {
      final release = _release(<AppReleaseAsset>[
        _asset(
          'LightNovelShelfPlus-V1.13.2-Plus-arm64-v8a.apk',
          sha256: _digest,
        ),
      ]);
      expect(release.androidApkFor(<String>['x86_64']), isNull);
      expect(release.installableApkFor(<String>['x86_64']), isNull);
    });
  });

  group('AppRelease.installableApkFor', () {
    test('带 sha256 的安装包可以自动下载安装', () {
      final release = _release(<AppReleaseAsset>[
        _asset(
          'LightNovelShelfPlus-V1.13.2-Plus-arm64-v8a.apk',
          sha256: _digest,
        ),
      ]);
      expect(release.installableApkFor(<String>['arm64-v8a'])?.sha256, _digest);
    });

    test('缺少 digest 时降级为打开 Release 页', () {
      final release = _release(<AppReleaseAsset>[
        _asset('LightNovelShelfPlus-V1.13.2-Plus-arm64-v8a.apk'),
      ]);
      expect(release.androidApkFor(<String>['arm64-v8a']), isNotNull);
      expect(release.installableApkFor(<String>['arm64-v8a']), isNull);
    });
  });
  group('AppRelease.decode', () {
    test('归一化 Plus 标签并读取 digest', () {
      final release = AppRelease.decode(<String, Object?>{
        'tag_name': 'V1.13.2-Plus',
        'html_url': 'https://example.com/tag/V1.13.2-Plus',
        'body': '  更新内容  ',
        'assets': <Object?>[
          <String, Object?>{
            'name': 'LightNovelShelfPlus-V1.13.2-Plus-arm64-v8a.apk',
            'browser_download_url': 'https://example.com/app.apk',
            'size': 2048,
            'digest': 'sha256:${_digest.toUpperCase()}',
          },
        ],
      });
      expect(release.version, '1.13.2');
      expect(release.notes, '更新内容');
      expect(release.assets.single.sha256, _digest);
      expect(release.installableApkFor(<String>['arm64-v8a']), isNotNull);
    });

    test('没有 digest 字段时留空，格式错误的资产被跳过', () {
      final release = AppRelease.decode(<String, Object?>{
        'tag_name': 'v1.12.3',
        'html_url': 'https://example.com/release',
        'assets': <Object?>[
          <String, Object?>{'name': 'broken.apk'},
          <String, Object?>{
            'name': 'LightNovelShelfPlus-V1.12.3-Plus-arm64-v8a.apk',
            'browser_download_url': 'https://example.com/app.apk',
            'size': 2048,
          },
        ],
      });
      expect(release.version, '1.12.3');
      expect(release.assets.single.sha256, isNull);
      expect(release.installableApkFor(<String>['arm64-v8a']), isNull);
    });

    test('重发包的版本身份带上 -Plus.N', () {
      final release = AppRelease.decode(<String, Object?>{
        'tag_name': 'V1.13.2-Plus.1',
        'html_url': 'https://example.com/release',
      });
      expect(release.version, '1.13.2-Plus.1');
      expect(release.assets, isEmpty);
    });

    test('缺少 tag 或页面链接时抛异常', () {
      expect(
        () => AppRelease.decode(<String, Object?>{
          'html_url': 'https://example.com',
        }),
        throwsA(isA<AppUpdateException>()),
      );
      expect(
        () => AppRelease.decode('not-a-map'),
        throwsA(isA<AppUpdateException>()),
      );
    });
  });

  group('AppUpdateRepository', () {
    late Directory directory;
    late _FakeStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('app_update_test');
      store = _FakeStore();
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    AppUpdateRepository build(http.Client client) =>
        AppUpdateRepository(
          store: store,
          client: client,
          updatesDirectory: directory,
        );

    test('限流或拒绝访问时抛 AppUpdateException', () async {
      for (final status in <int>[403, 429]) {
        final repository = build(
          MockClient((request) async => http.Response('rate limited', status)),
        );
        await expectLater(
          repository.fetchLatest(),
          throwsA(isA<AppUpdateException>()),
        );
      }
    });

    test('非 200 与畸形 JSON 都抛 AppUpdateException', () async {
      final bodies = <String>[
        'boom',
        '{"tag_name":',
        '[]',
        '{"html_url":"https://example.com"}',
      ];
      final statuses = <int>[500, 200, 200, 200];
      for (var i = 0; i < bodies.length; i++) {
        final repository = build(
          MockClient((request) async => http.Response(bodies[i], statuses[i])),
        );
        await expectLater(
          repository.fetchLatest(),
          throwsA(isA<AppUpdateException>()),
        );
      }
    });

    test('合法响应解析出 Plus 版本与资产', () async {
      final repository = build(
        MockClient(
          (request) async => http.Response(
            jsonEncode(<String, Object?>{
              'tag_name': 'V1.13.2-Plus',
              'html_url': 'https://example.com/release',
              'assets': <Object?>[
                <String, Object?>{
                  'name': 'LightNovelShelfPlus-V1.13.2-Plus-arm64-v8a.apk',
                  'browser_download_url': 'https://example.com/app.apk',
                  'size': 2048,
                },
              ],
            }),
            200,
          ),
        ),
      );
      final release = await repository.fetchLatest();
      expect(release.version, '1.13.2');
      expect(release.androidApkFor(<String>['arm64-v8a']), isNotNull);
      expect(release.installableApkFor(<String>['arm64-v8a']), isNull);
    });

    test('digest 不匹配时抛异常并删掉 .part', () async {
      const body = 'apk-bytes';
      final asset = AppReleaseAsset(
        name: 'LightNovelShelfPlus-V1.13.2-Plus-arm64-v8a.apk',
        url: Uri.parse('https://example.com/app.apk'),
        size: utf8.encode(body).length,
        sha256: List<String>.filled(64, 'b').join(),
      );
      final repository = build(
        MockClient((request) async => http.Response(body, 200)),
      );
      await expectLater(
        repository.downloadApk(_release(<AppReleaseAsset>[asset]), asset),
        throwsA(isA<AppUpdateException>()),
      );
      expect(
        await directory.list().map((e) => e.uri.pathSegments.last).toList(),
        isEmpty,
      );
    });

    test('下载成功后校验通过并复用已下载的包', () async {
      const body = 'apk-bytes';
      final asset = AppReleaseAsset(
        name: 'LightNovelShelfPlus-V1.13.2-Plus-arm64-v8a.apk',
        url: Uri.parse('https://example.com/app.apk'),
        size: utf8.encode(body).length,
        sha256: sha256.convert(utf8.encode(body)).toString(),
      );
      var requests = 0;
      final repository = build(
        MockClient((request) async {
          requests++;
          return http.Response(body, 200);
        }),
      );
      final release = _release(<AppReleaseAsset>[asset]);
      final file = await repository.downloadApk(release, asset);
      expect(await file.readAsString(), body);
      expect(file.path.endsWith('.apk'), isTrue);
      expect(await File('${file.path}.part').exists(), isFalse);
      final again = await repository.downloadApk(release, asset);
      expect(again.path, file.path);
      expect(requests, 1);
    });

    test('只删旧版本下载文件，保留当前版本并保持幂等', () async {
      final files = <File>[
        File(
          '${directory.path}/1.12.0-LightNovelShelfPlus-V1.12.0-Plus-arm64-v8a.apk',
        ),
        File(
          '${directory.path}/1.12.0-LightNovelShelfPlus-V1.12.0-Plus-arm64-v8a.apk.part',
        ),
        File(
          '${directory.path}/1.13.2-LightNovelShelfPlus-V1.13.2-Plus-arm64-v8a.apk',
        ),
        File('${directory.path}/notes.txt'),
      ];
      for (final file in files) {
        await file.writeAsString('x');
      }
      final repository = build(
        MockClient((request) async => http.Response('', 200)),
      );
      await repository.cleanInstalledApks('1.13.2');
      final names =
          await directory.list().map((e) => e.uri.pathSegments.last).toList();
      expect(names..sort(), <String>[
        '1.13.2-LightNovelShelfPlus-V1.13.2-Plus-arm64-v8a.apk',
        'notes.txt',
      ]);
      await repository.cleanInstalledApks('1.13.2');
      expect(await directory.list().length, 2);
    });

    test('更新目录不存在时直接返回', () async {
      final missing = Directory('${directory.path}/missing');
      final repository = AppUpdateRepository(
        store: store,
        updatesDirectory: missing,
      );
      await repository.cleanInstalledApks('1.13.2');
      expect(await missing.exists(), isFalse);
    });
  });
}
