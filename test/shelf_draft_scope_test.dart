import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lightnovel_shelf_plus/data/settings/app_settings.dart';
import 'package:lightnovel_shelf_plus/data/repositories/local_comic_shelf_repository.dart';
import 'package:lightnovel_shelf_plus/features/shelf/shelf_screen.dart';
import 'package:lightnovel_shelf_plus/features/shelf/widgets/shelf_folder_tile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel_shelf_plus/core/network/request_scheduler.dart';
import 'package:lightnovel_shelf_plus/core/network/signalr_connection.dart';
import 'package:lightnovel_shelf_plus/data/api/api_client.dart';
import 'package:lightnovel_shelf_plus/data/api/models.dart';
import 'package:lightnovel_shelf_plus/data/providers.dart';
import 'package:lightnovel_shelf_plus/data/repositories/book_metadata_cache.dart';
import 'package:lightnovel_shelf_plus/core/platform/stores.dart';
import 'package:lightnovel_shelf_plus/data/repositories/shelf_repository.dart';
import 'package:lightnovel_shelf_plus/data/session/auth_controller.dart';
import 'package:lightnovel_shelf_plus/features/shelf/shelf_editor_controller.dart';

const String _now = '2026-01-01T00:00:00Z';

ShelfItem _novel(int id, {List<String> parents = const <String>[]}) =>
    ShelfItem.book(
      type: ShelfItemType.novel,
      id: id,
      index: id,
      parents: parents,
      updatedAt: _now,
    );

ShelfItem _folder(String id, {List<String> parents = const <String>[]}) =>
    ShelfItem.folder(
      id: id,
      index: 0,
      parents: parents,
      updatedAt: _now,
      title: id,
    );

class _Api extends ApiClient {
  _Api()
    : super(
        signalR: SignalRConnection(
          endpoint: 'http://localhost/hub',
          accessTokenFactory: () async => null,
        ),
        scheduler: RateLimitRequestScheduler(),
        headers: () async => const <String, String>{},
      );

  /// 根层：小说 1、小说 2、文件夹 f（里面有小说 3）
  List<ShelfItem> items = <ShelfItem>[
    _novel(1),
    _novel(2),
    _folder('f'),
    _novel(3, parents: <String>['f']),
  ];

  Map<String, Object?>? lastSave;
  final Set<int> missingBooks = {};

  @override
  Future<T> invoke<T>(
    String methodName,
    Object? params,
    T Function(Object?) decode, {
    RequestPriority priority = RequestPriority.interactive,
    CancelToken? cancelToken,
  }) async {
    switch (methodName) {
      case 'GetBookShelf':
        return decode({
          'data': items.map((item) => item.encode()).toList(),
          'ver': '20220211',
        });
      case 'GetBookListByIds':
        return decode([
          for (final id in (params as Map)['Ids'] as List<int>)
            if (!missingBooks.contains(id))
              {
                'Id': id,
                'Type': items.any((item) => item.isComic && item.bookId == id)
                    ? 'Comic'
                    : 'Novel',
                'Title': 'Book $id',
                'Author': 'Author',
                'Cover': 'https://img.test/$id.jpg',
                'LastUpdatedAt': _now,
              },
        ]);
      case 'SaveBookShelf':
        lastSave = params as Map<String, Object?>;
        items = (params['data']! as List).map(ShelfItem.decode).toList();
        return decode(null);
      default:
        throw StateError(methodName);
    }
  }
}

class _MemoryStore implements KeyValueStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

class _LocalComics extends LocalComicShelfController {
  @override
  Future<List<LocalShelfComic>> build() async => [];
}

ProviderContainer _container(_Api api) => ProviderContainer(
  overrides: [
    apiClientProvider.overrideWithValue(api),
    settingsControllerProvider.overrideWith(
      (ref) => SettingsController(
        _MemoryStore(),
        const AppSettings(shelfSeriesView: false),
      ),
    ),
    localComicShelfProvider.overrideWith(_LocalComics.new),
    bookMetadataCacheProvider.overrideWithValue(
      BookMetadataCache(_MemoryStore()),
    ),
    authSnapshotProvider.overrideWithValue(
      const AuthenticationSnapshot(status: AuthenticationStatus.authenticated),
    ),
  ],
);

/// 订阅后再读，免得 autoDispose 的层级 provider 读完就被回收。
List<String> _levelKeys(ProviderContainer container, List<String> parents) {
  final provider = shelfLevelProvider(shelfLevelKey(parents));
  container.listen(provider, (_, _) {});
  return container.read(provider).siblings.map((item) => item.key).toList();
}

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));
  late _Api api;
  late ProviderContainer container;
  late ShelfEditorController editor;

  setUp(() async {
    api = _Api();
    container = _container(api);
    addTearDown(container.dispose);
    await container.read(shelfProvider.future);
    editor = container.read(shelfEditorProvider.notifier);
  });

  testWidgets('Plus 网格与列表保留文件夹入口，筛选可见条目且不修改书架', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ShelfScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ShelfFolderTile), findsOneWidget);
    expect(find.text('Book 1'), findsOneWidget);
    expect(find.text('Book 3'), findsNothing);
    await tester.tap(find.byTooltip('切换到列表视图'));
    await tester.pumpAndSettle();
    expect(find.text('f'), findsOneWidget);
    await tester.longPress(find.text('f'));
    await tester.pumpAndSettle();
    expect(container.read(shelfEditorProvider).selected, {'FOLDER:f'});
    container.read(shelfEditorProvider.notifier).setMode(ShelfMode.browse);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('只看漫画'));
    await tester.pumpAndSettle();
    expect(find.text('这里没有漫画'), findsOneWidget);
    expect(api.lastSave, isNull);
    expect(api.items.length, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('在子文件夹新建后返回根层共享未保存草稿', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const ShelfScreen()),
        GoRoute(
          path: '/shelf/folder',
          builder: (_, state) => ShelfScreen(
            parents: state.uri.queryParametersAll['parent'] ?? [],
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ShelfFolderTile));
    await tester.pumpAndSettle();
    expect(find.text('Book 3'), findsOneWidget);
    await tester.tap(find.byTooltip('管理书架'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建文件夹'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Child');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(
      container
          .read(shelfDraftProvider)!
          .items
          .singleWhere((item) => item.title == 'Child')
          .parents,
      ['f'],
    );
    router.pop();
    await tester.pumpAndSettle();
    expect(container.read(shelfDirtyProvider), isTrue);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('Child'), findsNothing);
    expect(api.lastSave, isNull);
    expect(tester.takeException(), isNull);
  });

  test('加载及保存保留多层文件夹和缺少详情的条目，写回固定新版协议', () async {
    api.items = [
      _folder('a'),
      _folder('b', parents: ['a']),
      _novel(7, parents: ['a', 'b']),
      const ShelfItem.book(
        type: ShelfItemType.comic,
        id: 8,
        index: 0,
        parents: ['a'],
        updatedAt: _now,
      ),
    ];
    api.missingBooks.add(7);
    await container.read(shelfProvider.notifier).reload();
    final snapshot = container.read(shelfProvider).value!;
    expect(snapshot.items.length, 4);
    expect(snapshot.books.map((book) => book.id), isNot(contains(7)));
    await container.read(shelfProvider.notifier).save(snapshot.toDraft());
    expect(api.lastSave!['ver'], '20260921');
    expect(api.items.map((item) => item.key).toSet(), {
      'FOLDER:a',
      'FOLDER:b',
      'NOVEL:7',
      'COMIC:8',
    });
    expect(api.items.firstWhere((item) => item.key == 'NOVEL:7').parents, [
      'a',
      'b',
    ]);
    final cached = (await container
        .read(bookMetadataCacheProvider)
        .readShelf())!;
    expect(
      cached.items.map((item) => item.encode()),
      api.items.map((item) => item.encode()),
    );
  });

  test('批量添加和移除小说不会移除已有文件夹或漫画', () async {
    api.items.add(
      const ShelfItem.book(
        type: ShelfItemType.comic,
        id: 8,
        index: 0,
        parents: ['f'],
        updatedAt: _now,
      ),
    );
    final controller = container.read(shelfProvider.notifier);
    expect(await controller.addBooks([4, 5, 4]), 2);
    expect(await controller.removeBooks([4, 5]), 2);
    expect(api.items.firstWhere((item) => item.key == 'NOVEL:3').parents, [
      'f',
    ]);
    expect(api.items.firstWhere((item) => item.key == 'COMIC:8').parents, [
      'f',
    ]);
    expect(api.items.any((item) => item.key == 'FOLDER:f'), isTrue);
  });

  test('漫画收藏状态和取消收藏通过服务端同步', () async {
    final controller = container.read(shelfProvider.notifier);
    expect(await controller.toggleBook(8, type: ShelfItemType.comic), isTrue);
    expect(await controller.contains(8, type: ShelfItemType.comic), isTrue);
    expect(
      api.items.firstWhere((item) => item.bookId == 8).type,
      ShelfItemType.comic,
    );
    expect(await controller.toggleBook(8, type: ShelfItemType.comic), isFalse);
    expect(await controller.contains(8, type: ShelfItemType.comic), isFalse);
    expect(api.items.any((item) => item.key == 'FOLDER:f'), isTrue);
  });

  test('未保存的移动立刻在目标层可见，原来那层不再有它', () {
    final root = container
        .read(shelfDraftProvider)!
        .items
        .firstWhere((item) => item.key == 'NOVEL:1');
    editor.beginSelection(root);
    editor.moveItems(keys: <String>{'NOVEL:1'}, destination: <String>['f']);

    // 移动过来的条目排在目标层开头。
    expect(_levelKeys(container, const <String>['f']), <String>[
      'NOVEL:1',
      'NOVEL:3',
    ]);
    expect(_levelKeys(container, const <String>[]), <String>[
      'FOLDER:f',
      'NOVEL:2',
    ]);
    // 草稿还没保存，服务端那份不动。
    expect(api.items.length, 4);
    expect(
      api.items.firstWhere((item) => item.key == 'NOVEL:1').parents,
      isEmpty,
    );
  });

  test('在子层新建的文件夹落在子层', () {
    editor.createFolder('新的', parents: const <String>['f']);

    final created = container
        .read(shelfDraftProvider)!
        .items
        .firstWhere((item) => !item.isBook && item.title == '新的');
    expect(created.parents, <String>['f']);
    expect(_levelKeys(container, const <String>['f']), contains(created.key));
    expect(
      _levelKeys(container, const <String>[]),
      isNot(contains(created.key)),
    );
  });

  test('子层的改动让整个书架都算有未保存改动', () {
    expect(container.read(shelfDirtyProvider), isFalse);
    editor.createFolder('新的', parents: const <String>['f']);
    expect(container.read(shelfDirtyProvider), isTrue);

    editor.discard();
    expect(container.read(shelfDirtyProvider), isFalse);
    expect(_levelKeys(container, const <String>['f']), <String>['NOVEL:3']);
  });

  test('层级派生数据按路径记忆化，草稿没换就不重算', () {
    final provider = shelfLevelProvider(shelfLevelKey(const <String>[]));
    container.listen(provider, (_, _) {});
    final first = container.read(provider);
    expect(identical(container.read(provider), first), isTrue);

    editor.createFolder('新的', parents: const <String>['f']);
    expect(identical(container.read(provider), first), isFalse);
  });
}
