/// 用书名末尾的卷号生成稳定的系列检索键。
///
/// 服务端系列条目缺失时，书架仍能把「作品名 1 / 作品名 2」归到一起。只剥离
/// 末尾明确的卷、册、集或纯数字，避免改动标题中间的数字。
String seriesTitleFromBookTitle(String title) {
  var value = title.trim();
  value = value.replaceFirst(
    RegExp(
      r'\s*(?:[（(]\s*)?(?:第\s*)?(?:\d+|[０-９]+|[〇零一二三四五六七八九十百千万萬两兩壹贰貳叁參肆伍陆陸柒捌玖拾佰仟]+|[ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩ]+|[IVXivx]+)\s*(?:卷|冊|册|集|話|话|巻)?\s*[）)]?\s*$',
    ),
    '',
  );
  return value.trim().isEmpty ? title.trim() : value.trim();
}

/// 返回书籍的稳定系列键。
///
/// 服务端的系列条目是权威来源。它可以正确表达带副标题或类似 `Logic.1`
/// 的卷号格式，不能用本地的正则猜测来覆盖。只有接口没有返回系列、或
/// 返回空白字符串时，才从书名末尾清除常见卷号作为兜底。
String seriesKeyForBook(String title, String? serverSeriesTitle) {
  final serverTitle = serverSeriesTitle?.trim();
  if (serverTitle?.isNotEmpty == true) return serverTitle!;
  return seriesTitleFromBookTitle(title);
}

/// 本地书架按稳定系列键分组。
String shelfSeriesKey(String title, String? serverSeriesTitle) {
  return seriesKeyForBook(title, serverSeriesTitle);
}

/// A connected group of books on the shelf.
///
/// [name] favors a server-provided series name, while [items] retains the
/// original shelf order.
class ShelfSeriesGroup<T> {
  const ShelfSeriesGroup({required this.name, required this.items});

  final String name;
  final List<T> items;
}

/// Groups shelf books using both available series identities.
///
/// A server series entry remains the preferred display name, but a title whose
/// volume marker was successfully removed is also an identity.  A book that
/// has both identities therefore bridges the two groups: for example, volume
/// 1 with no server entry and volume 2 with a server entry can still appear in
/// the same series.  Only a *changed* title is used as a derived identity, so
/// unrelated books with an unchanged title are not linked by this heuristic.
List<ShelfSeriesGroup<T>> groupShelfSeries<T>(
  Iterable<T> items, {
  required String Function(T item) titleOf,
  required String? Function(T item) serverSeriesTitleOf,
}) {
  final values = items.toList(growable: false);
  final parents = List<int>.generate(values.length, (index) => index);

  int find(int index) {
    while (parents[index] != index) {
      parents[index] = parents[parents[index]];
      index = parents[index];
    }
    return index;
  }

  void union(int left, int right) {
    final leftRoot = find(left);
    final rightRoot = find(right);
    if (leftRoot != rightRoot) parents[rightRoot] = leftRoot;
  }

  final firstByServerName = <String, int>{};
  final firstByDerivedTitle = <String, int>{};
  for (var index = 0; index < values.length; index++) {
    final item = values[index];
    final serverName = serverSeriesTitleOf(item)?.trim();
    if (serverName?.isNotEmpty == true) {
      final first = firstByServerName.putIfAbsent(serverName!, () => index);
      union(index, first);
    }

    final title = titleOf(item).trim();
    final derivedTitle = seriesTitleFromBookTitle(title);
    if (derivedTitle.isNotEmpty && derivedTitle != title) {
      final first = firstByDerivedTitle.putIfAbsent(derivedTitle, () => index);
      union(index, first);
    }
  }

  final membersByRoot = <int, List<T>>{};
  final rootsInOrder = <int>[];
  for (var index = 0; index < values.length; index++) {
    final root = find(index);
    final members = membersByRoot.putIfAbsent(root, () {
      rootsInOrder.add(root);
      return <T>[];
    });
    members.add(values[index]);
  }

  return rootsInOrder
      .map((root) {
        final members = membersByRoot[root]!;
        String? serverName;
        for (final member in members) {
          final candidate = serverSeriesTitleOf(member)?.trim();
          if (candidate?.isNotEmpty == true) {
            serverName = candidate;
            break;
          }
        }
        return ShelfSeriesGroup<T>(
          name: serverName ?? seriesTitleFromBookTitle(titleOf(members.first)),
          items: List<T>.unmodifiable(members),
        );
      })
      .toList(growable: false);
}
