import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel_shelf_plus/core/network/request_scheduler.dart';
import 'package:lightnovel_shelf_plus/core/network/signalr_connection.dart';
import 'package:lightnovel_shelf_plus/core/platform/cache_file_store.dart';
import 'package:lightnovel_shelf_plus/core/platform/stores.dart';
import 'package:lightnovel_shelf_plus/data/api/api_client.dart';
import 'package:lightnovel_shelf_plus/data/api/envelope.dart';
import 'package:lightnovel_shelf_plus/data/api/models.dart';
import 'package:lightnovel_shelf_plus/data/repositories/book_metadata_cache.dart';
import 'package:lightnovel_shelf_plus/data/repositories/reader_font_repository.dart';
import 'package:lightnovel_shelf_plus/features/reader/reader_chapter_prerenderer.dart';

class _CountingStore implements KeyValueStore {
  final Map<String, String> values = <String, String>{};
  int readCount = 0;
  int writeCount = 0;

  @override
  Future<String?> read(String key) async {
    readCount += 1;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writeCount += 1;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _FakeNovelApi extends ApiClient {
  _FakeNovelApi()
    : super(
        signalR: SignalRConnection(
          endpoint: 'http://localhost/hub',
          accessTokenFactory: () async => null,
        ),
        scheduler: RateLimitRequestScheduler(),
        headers: () async => const <String, String>{},
      );

  @override
  Future<T> invoke<T>(
    String methodName,
    Object? params,
    T Function(Object? value) decode, {
    RequestPriority priority = RequestPriority.interactive,
    CancelToken? cancelToken,
  }) async {
    if (methodName != 'GetNovelContent') {
      throw UnimplementedError(methodName);
    }
    final args = params! as Map<String, Object?>;
    final sortNum = args['SortNum']! as int;
    return decode(<String, dynamic>{
      'Chapter': <String, dynamic>{
        'Id': 100 + sortNum,
        'BookId': 7,
        'Title': '第$sortNum章',
        'Content': '<p>正文 $sortNum</p>',
        'Font': 'https://fonts.invalid/chapter-$sortNum.woff2',
        'SortNum': sortNum,
        'Chapters': const <String>['第1章', '第2章', '第3章', '第4章', '第5章'],
        'CanEdit': false,
      },
      'ReadPosition': null,
    });
  }
}

class _FakeFontRepository extends ReaderFontRepository {
  _FakeFontRepository(super.api);

  final List<String> prefetched = <String>[];
  final List<String> registered = <String>[];

  @override
  Future<void> prefetchToDisk(
    String? fontUrl, {
    bool cacheEnabled = true,
    int cacheLimit = 30,
    CancelToken? cancelToken,
  }) async {
    if (fontUrl != null) prefetched.add(fontUrl);
  }

  @override
  Future<String?> loadFamily(
    String? fontUrl, {
    bool cacheEnabled = true,
    int cacheLimit = 30,
    RequestPriority priority = RequestPriority.interactive,
    CancelToken? cancelToken,
  }) async {
    if (fontUrl == null) return null;
    registered.add(fontUrl);
    return 'fake-family-$fontUrl';
  }
}

BookListItem _sampleBook(int id) => BookListItem(
  id: id,
  type: BookType.novel,
  title: '示例书 $id',
  seriesTitle: '示例系列',
  coverUrl: 'https://img.invalid/$id.jpg',
  coverPlaceholder: null,
  authorName: '作者',
  lastUpdatedAt: DateTime.utc(2026, 1, 1),
  level: null,
  interiorLevel: null,
  category: null,
);

void main() {
  test('FileCacheStore migrates legacy entries and deletes legacy key', () async {
    final tempDir = await Directory.systemTemp.createTemp('lns-cache-test-');
    addTearDown(() => tempDir.delete(recursive: true));

    final legacy = _CountingStore()..values['test.key'] = '{"ok":true}';
    final store = FileCacheStore(
      legacy: legacy,
      directoryProvider: () async => tempDir,
    );

    expect(await store.read('test.key'), '{"ok":true}');
    // 迁移后旧存储键已删除，后续读取直接命中文件缓存。
    expect(legacy.values.containsKey('test.key'), isFalse);
    final readsBefore = legacy.readCount;
    expect(await store.read('test.key'), '{"ok":true}');
    expect(legacy.readCount, readsBefore);

    await store.delete('test.key');
    expect(await store.read('test.key'), isNull);
  });

  test('BookMetadataCache reuses in-memory mirror and clears cleanly', () async {
    final store = _CountingStore();
    final cache = BookMetadataCache(store);

    await cache.putAll(<BookListItem>[_sampleBook(1), _sampleBook(2)]);
    final readsAfterPut = store.readCount;

    final resolved = await cache.resolve(
      <int>[1, 2],
      (_) async => fail('Should not hit network loader on cache hit'),
    );
    expect(resolved.map((b) => b.id).toList(), <int>[1, 2]);
    expect(store.readCount, readsAfterPut);

    await cache.clear();
    expect(store.values.containsKey(bookMetadataCacheKey), isFalse);
  });

  test('unwrapSignalRResponseAsync inflates large gzip payloads off-thread', () async {
    final rnd = math.Random(42);
    final largeList = List<Map<String, Object?>>.generate(
      400,
      (i) => <String, Object?>{
        'id': i,
        'text': List<String>.generate(
          40,
          (_) => rnd.nextInt(1 << 20).toRadixString(36),
        ).join('-'),
      },
    );
    final compressed = gzip.encode(utf8.encode(jsonEncode(largeList)));
    final encoded = base64Encode(compressed);
    expect(encoded.length, greaterThan(8192));

    final unwrapped = await unwrapSignalRResponseAsync(<String, Object?>{
      'Success': true,
      'Response': encoded,
    });
    expect(unwrapped, isA<List<dynamic>>());
    expect((unwrapped! as List<dynamic>).length, 400);
  });

  test(
    'ReaderChapterPrerenderer enforces LRU cap and defers font registration',
    () async {
      final api = _FakeNovelApi();
      final fonts = _FakeFontRepository(api);
      final prerenderer = ReaderChapterPrerenderer(
        api: api,
        fonts: fonts,
        bookId: 7,
        maxCachedChapters: 3,
      );
      addTearDown(prerenderer.dispose);

      // 预加载不立即注册引擎字体，只预取到磁盘。
      final pre = await prerenderer.prerender(
        sortNum: 1,
        convert: null,
        fontCacheEnabled: true,
        fontCacheLimit: 30,
        registerFont: false,
      );
      expect(pre, isNotNull);
      expect(pre!.fontFamily, isNull);
      expect(pre.needsFontRegistration, isTrue);
      expect(fonts.prefetched, hasLength(1));
      expect(fonts.registered, isEmpty);

      // 真正进入窗口时才注册字体。
      final ready = await prerenderer.ensureFontRegistered(
        pre,
        convert: null,
        fontCacheEnabled: true,
        fontCacheLimit: 30,
      );
      expect(ready.fontFamily, contains('chapter-1.woff2'));
      expect(fonts.registered, hasLength(1));

      // 超过 maxCachedChapters 时按 LRU 淘汰最旧章节。
      for (final sortNum in <int>[2, 3, 4, 5]) {
        await prerenderer.open(
          sortNum: sortNum,
          convert: null,
          fresh: false,
          fontCacheEnabled: true,
          fontCacheLimit: 30,
        );
      }
      expect(prerenderer.cachedCount, 3);
    },
  );
}
