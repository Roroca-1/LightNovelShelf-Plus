import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel_shelf_plus/core/platform/stores.dart';

class _MemoryStore implements KeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  test(
    'KeyValueCredentialStore isolates credential keys and supports deletion',
    () async {
      final backing = _MemoryStore();
      final store = KeyValueCredentialStore(backing);

      await store.write('token', 'secret');

      expect(await store.read('token'), 'secret');
      expect(backing.values['credentials.token'], 'secret');

      await store.delete('token');
      expect(await store.read('token'), isNull);
    },
  );
}
