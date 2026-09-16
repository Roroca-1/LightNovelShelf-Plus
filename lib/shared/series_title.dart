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

/// 本地书架按标题分组；服务端名称只在标题无法产生键时兜底。
String shelfSeriesKey(String title, String? serverSeriesTitle) {
  final derived = seriesTitleFromBookTitle(title);
  return derived.isEmpty ? (serverSeriesTitle?.trim() ?? '') : derived;
}
