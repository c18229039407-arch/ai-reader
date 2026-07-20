import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_reader/models/models.dart';
import 'package:ai_reader/services/epub_loader.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造一个最小 EPUB（zip）字节流。
Uint8List buildEpub({
  required Map<String, String> chapters, // 文件名 → HTML
  Uint8List? coverImage,
  String coverName = 'cover.jpg',
  String title = '测试书',
}) {
  final archive = Archive();
  void add(String name, List<int> data) =>
      archive.addFile(ArchiveFile(name, data.length, data));

  add('mimetype', utf8.encode('application/epub+zip'));
  add('META-INF/container.xml', utf8.encode('''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>'''));

  final manifest = StringBuffer();
  final spine = StringBuffer();
  final navPoints = StringBuffer();
  var i = 0;
  for (final e in chapters.entries) {
    add('OPS/${e.key}', utf8.encode(e.value));
    manifest.write(
        '<item id="c$i" href="${e.key}" media-type="application/xhtml+xml"/>');
    spine.write('<itemref idref="c$i"/>');
    navPoints.write(
        '<navPoint id="n$i" playOrder="${i + 1}"><navLabel><text>第${i + 1}节</text></navLabel><content src="${e.key}"/></navPoint>');
    i++;
  }
  if (coverImage != null) {
    add('OPS/$coverName', coverImage);
    manifest.write(
        '<item id="cover-img" href="$coverName" media-type="image/jpeg"/>');
  }
  add('OPS/content.opf', utf8.encode('''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:title>$title</dc:title><dc:creator>测试作者</dc:creator>
<dc:identifier id="id">test-book</dc:identifier><dc:language>zh</dc:language>
</metadata>
<manifest>$manifest<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest>
<spine toc="ncx">$spine</spine>
</package>'''));
  add('OPS/toc.ncx', utf8.encode('''<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
<head><meta name="dtb:uid" content="test-book"/></head>
<docTitle><text>$title</text></docTitle>
<navMap>$navPoints</navMap>
</ncx>'''));

  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  group('维基文库导出清理', () {
    test('导航残留、导出说明、about 页被过滤', () async {
      final epub = buildEpub(title: '骆驼祥子', chapters: {
        'title.xhtml':
            '<html><body><p>骆驼祥子</p><p>以2026年7月20日从维基文库导出</p></body></html>',
        'about.xhtml':
            '<html><body><p>MediaWiki:Wsexport_about</p><p>About this digital edition</p></body></html>',
        'c1.xhtml': '<html><body><table><tr><td>目錄</td><td>骆驼祥子</td>'
            '<td>◀上一章</td><td>下一章▶</td></tr></table>'
            '<p>${'我們所要介紹的是祥子，不是駱駝。' * 20}</p></body></html>',
      });
      final book = await loadEpub(epub);

      // title 页（只剩书名+导出说明）与 about 页整章被丢弃
      expect(book.chapters, hasLength(1));
      final paras = book.chapters.single.paragraphs;
      expect(paras.join(), isNot(contains('目錄')));
      expect(paras.join(), isNot(contains('上一章')));
      expect(paras.join(), isNot(contains('下一章')));
      expect(paras.join(), isNot(contains('维基文库导出')));
      expect(paras.join(), contains('祥子'));
    });
  });

  group('EPUB 内嵌封面提取', () {
    test('>8KB 的 cover 图被提取', () async {
      final cover = Uint8List.fromList(List.filled(20 * 1024, 0xAB));
      final epub = buildEpub(
        chapters: {'c1.xhtml': '<html><body><p>${'正文' * 200}</p></body></html>'},
        coverImage: cover,
      );
      final book = await loadEpub(epub);
      expect(book.coverBytes, isNotNull);
      expect(book.coverBytes!.length, cover.length);
    });

    test('只有小图（logo）时不当封面', () async {
      final epub = buildEpub(
        chapters: {'c1.xhtml': '<html><body><p>${'正文' * 200}</p></body></html>'},
        coverImage: Uint8List.fromList(List.filled(2 * 1024, 0xAB)),
        coverName: 'wikisource-logo.png',
      );
      final book = await loadEpub(epub);
      expect(book.coverBytes, isNull);
    });

    test('回归：大尺寸站标 logo 也不当封面（维基文库冰山 logo 事故）', () async {
      final epub = buildEpub(
        chapters: {'c1.xhtml': '<html><body><p>${'正文' * 200}</p></body></html>'},
        coverImage: Uint8List.fromList(List.filled(40 * 1024, 0xAB)),
        coverName: 'images/Wikisource-logo.svg.png',
      );
      final book = await loadEpub(epub);
      expect(book.coverBytes, isNull,
          reason: 'logo/icon/badge 命名的图不论多大都不能当封面');
    });
  });

  group('句级高亮模型', () {
    test('范围高亮 JSON 往返', () {
      final h = Highlight(
        locator: const Locator(2, 5),
        colorIndex: 1,
        createdAt: DateTime(2026, 7, 20),
        start: 10,
        end: 24,
        snippet: '这是被高亮的一句话',
      );
      final back = Highlight.fromJson(
          jsonDecode(jsonEncode(h.toJson())) as Map<String, dynamic>);
      expect(back.isRange, isTrue);
      expect(back.start, 10);
      expect(back.end, 24);
      expect(back.snippet, '这是被高亮的一句话');
    });

    test('旧数据（无 start/end）兼容为整段高亮', () {
      final back = Highlight.fromJson({
        'locator': '1:3',
        'colorIndex': 0,
        'createdAt': '2026-01-01T00:00:00.000',
      });
      expect(back.isRange, isFalse);
      expect(back.overlaps(0, 5), isTrue); // 整段视为覆盖任意范围
    });

    test('重叠判定', () {
      final h = Highlight(
        locator: const Locator(0, 0),
        colorIndex: 0,
        createdAt: DateTime(2026),
        start: 10,
        end: 20,
      );
      expect(h.overlaps(15, 25), isTrue);
      expect(h.overlaps(20, 30), isFalse); // 相邻不算重叠
      expect(h.overlaps(0, 10), isFalse);
    });
  });
}
