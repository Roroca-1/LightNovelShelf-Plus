import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel_shelf_plus/data/app_update.dart';

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

  group('isNewerVersion', () {
    test('Plus 标签与纯版本号相等时不提示更新', () {
      expect(isNewerVersion('V1.13.2-Plus', '1.13.2'), isFalse);
      expect(isNewerVersion('V1.12.3-Plus.1', '1.12.3'), isFalse);
      expect(isNewerVersion('V1.13.2-Plus', 'V1.13.2-Plus'), isFalse);
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
}
