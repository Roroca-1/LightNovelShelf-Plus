import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel_shelf_plus/shared/series_title.dart';

void main() {
  group('seriesTitleFromBookTitle', () {
    test('移除中文卷号，供系列标题检索使用', () {
      expect(seriesTitleFromBookTitle('某本小说 第一卷'), '某本小说');
      expect(seriesTitleFromBookTitle('某本小说 第二卷'), '某本小说');
      expect(seriesTitleFromBookTitle('某本小说 第十卷'), '某本小说');
    });

    test('保留非卷号的标题内容', () {
      expect(seriesTitleFromBookTitle('86－不存在的战区'), '86－不存在的战区');
    });
  });
}
