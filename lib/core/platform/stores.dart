import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 凭据存储（会话令牌 / 刷新令牌 / 访客 ID）。
abstract class CredentialStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// 普通键值存储（设置、缓存）。
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PreferencesKeyValueStore implements KeyValueStore {
  PreferencesKeyValueStore(this._preferences);

  final SharedPreferences _preferences;

  static Future<PreferencesKeyValueStore> open() async =>
      PreferencesKeyValueStore(await SharedPreferences.getInstance());

  @override
  Future<String?> read(String key) async => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) async {
    await _preferences.setString(key, value);
  }

  @override
  Future<void> delete(String key) async {
    await _preferences.remove(key);
  }
}

/// 仅供无法访问 iOS Keychain 的无签名安装包保存凭据。
///
/// 值仍在应用沙盒内，但不具备 Keychain 的硬件/系统级保护；签名正常的安装
/// 必须继续使用 [SecureCredentialStore]。
class KeyValueCredentialStore implements CredentialStore {
  KeyValueCredentialStore(this._store);

  static const String _prefix = 'credentials.';
  final KeyValueStore _store;

  String _key(String key) => '$_prefix$key';

  @override
  Future<String?> read(String key) => _store.read(_key(key));

  @override
  Future<void> write(String key, String value) =>
      _store.write(_key(key), value);

  @override
  Future<void> delete(String key) => _store.delete(_key(key));
}

/// 服务端要求密码用 SHA-256 十六进制提交。
class PasswordHasher {
  const PasswordHasher();

  String sha256Hex(String value) =>
      sha256.convert(utf8.encode(value)).toString();
}
