import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'stores.dart';

/// 将大型 JSON 缓存独立落盘到 `ApplicationSupport/json-cache/`，避免把上千条
/// 书目和书架快照塞进 `SharedPreferences`（它会在启动时把所有键值常驻内存）。
///
/// 若文件尚不存在但旧 `legacy` 存储里仍有值，读取时会自动迁移并删除旧键。
class FileCacheStore implements KeyValueStore {
  FileCacheStore({
    KeyValueStore? legacy,
    Future<Directory> Function()? directoryProvider,
  }) : _legacy = legacy,
       _directoryProvider = directoryProvider ?? _defaultDirectory;

  final KeyValueStore? _legacy;
  final Future<Directory> Function() _directoryProvider;
  Future<Directory>? _dirFuture;

  static Future<Directory> _defaultDirectory() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}${Platform.pathSeparator}json-cache');
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _fileFor(String key) async {
    final dir = await (_dirFuture ??= _directoryProvider());
    final digest = md5.convert(utf8.encode(key)).toString();
    return File('${dir.path}${Platform.pathSeparator}$digest.json');
  }

  @override
  Future<String?> read(String key) async {
    try {
      final file = await _fileFor(key);
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (_) {
      // 文件损坏或不可读时继续尝试回退旧存储。
    }
    final legacy = _legacy;
    if (legacy == null) return null;
    final value = await legacy.read(key);
    if (value == null) return null;
    try {
      await write(key, value);
      await legacy.delete(key);
    } catch (_) {
      // 迁移失败不影响本次返回。
    }
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    final file = await _fileFor(key);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(value, flush: false);
    await temp.rename(file.path);
    final legacy = _legacy;
    if (legacy != null) {
      try {
        await legacy.delete(key);
      } catch (_) {
        // 清理旧键失败不影响新缓存写入。
      }
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      final file = await _fileFor(key);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 删除失败忽略。
    }
    final legacy = _legacy;
    if (legacy != null) {
      try {
        await legacy.delete(key);
      } catch (_) {}
    }
  }
}
