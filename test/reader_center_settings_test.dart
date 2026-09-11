import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel_shelf_plus/data/settings/app_settings.dart';

void main() {
  test('正文居中设置可以保存、恢复，旧配置默认关闭', () {
    final original = ReaderPreferences.decode(<String, dynamic>{});
    expect(original.centeredTextEnabled, isFalse);
    final enabled = original.copyWith(centeredTextEnabled: true);
    expect(enabled, isNot(original));
    expect(ReaderPreferences.decode(enabled.encode()), enabled);
    expect(enabled.copyWith(centeredTextEnabled: false), original);
  });
}
