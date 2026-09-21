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

  group('seriesKeyForBook', () {
    test('优先采用服务端系列条目，避免误判带副标题的卷号', () {
      expect(
        seriesKeyForBook('夏洛克+侦探学园 Logic.1 犯罪王之孙辨倒名侦探', '夏洛克侦探学园'),
        '夏洛克侦探学园',
      );
      expect(seriesKeyForBook('某本小说 第一卷：副标题', '服务端系列'), '服务端系列');
    });

    test('仅在服务端系列缺失或为空时从书名去除卷号', () {
      expect(seriesKeyForBook('某本小说 第一卷', null), '某本小说');
      expect(seriesKeyForBook('某本小说 第二卷', '  '), '某本小说');
    });
  });

  group('groupShelfSeries', () {
    test('用去卷号标题把缺少服务端系列的首册接入服务端系列', () {
      final groups = groupShelfSeries(
        <({String title, String? serverSeries})>[
          (title: '《人生重来的恶德领主不知悔改！ 1》', serverSeries: null),
          (title: '《人生重来的恶德领主不知悔改！ 2》', serverSeries: 'やり直し悪徳領主に…'),
          (title: '《人生重来的恶德领主不知悔改！ 3》', serverSeries: 'やり直し悪徳領主に…'),
        ],
        titleOf: (book) => book.title,
        serverSeriesTitleOf: (book) => book.serverSeries,
      );

      expect(groups, hasLength(1));
      expect(groups.single.name, 'やり直し悪徳領主に…');
      expect(groups.single.items.map((book) => book.title), hasLength(3));
    });

    test('未实际去除卷号的同名书不会仅凭标题被合并', () {
      final groups = groupShelfSeries(
        <({String title, String? serverSeries})>[
          (title: '同名作品', serverSeries: '系列甲'),
          (title: '同名作品', serverSeries: '系列乙'),
        ],
        titleOf: (book) => book.title,
        serverSeriesTitleOf: (book) => book.serverSeries,
      );

      expect(groups, hasLength(2));
    });
  });
}
