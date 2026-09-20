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
