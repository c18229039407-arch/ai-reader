/// A4 中立聚合搜索入口：把书名交给系统浏览器（PRD §8 合规设计）。
/// App 只负责打开链接；查找、判断、下载都发生在 App 外，由用户自己完成，
/// 下载到的文件再通过「导入书籍」进书架。不硬编码任何指向盗版站的逻辑。
library;

class FindOnlineLink {
  const FindOnlineLink(this.label, this.hint, this.uri);

  final String label;
  final String hint;
  final Uri uri;
}

List<FindOnlineLink> findOnlineLinks(String title) {
  final q = title.trim();
  return [
    FindOnlineLink(
      '网页搜索',
      '用浏览器通用搜索这本书',
      Uri.parse('https://www.bing.com/search?q=${Uri.encodeQueryComponent(q)}'),
    ),
    FindOnlineLink(
      '豆瓣图书',
      '看简介、评分与版本信息',
      Uri.parse(
          'https://search.douban.com/book/subject_search?search_text=${Uri.encodeQueryComponent(q)}'),
    ),
    FindOnlineLink(
      '微信读书',
      '正版电子书（部分可免费读）',
      Uri.parse(
          'https://weread.qq.com/web/search/global?keyword=${Uri.encodeQueryComponent(q)}'),
    ),
    FindOnlineLink(
      '孔夫子旧书网',
      '绝版书/二手纸质书',
      Uri.parse(
          'https://search.kongfz.com/product/?keyword=${Uri.encodeQueryComponent(q)}'),
    ),
  ];
}
