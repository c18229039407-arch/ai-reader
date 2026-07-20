import 'package:ai_reader/services/epub_loader.dart';
import 'package:ai_reader/services/paginator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('htmlToBlocks 轻量富文本解析', () {
    test('标题分级 h1/h2/h3+，引用与正文', () {
      final blocks = htmlToBlocks('''
        <h1>第一章</h1>
        <h2>第一节</h2>
        <h4>小标题</h4>
        <blockquote>这是一段引用文字。</blockquote>
        <p>这是正文段落。</p>
      ''');
      expect(blocks.map((b) => b.kind).toList(), [
        ParaKind.h1,
        ParaKind.h2,
        ParaKind.h3, // h4-6 归并到 h3
        ParaKind.quote,
        ParaKind.body,
      ]);
      expect(blocks[0].text, '第一章');
      expect(blocks[3].text, '这是一段引用文字。');
    });

    test('行内粗斜体：范围落在干净文本上', () {
      final blocks =
          htmlToBlocks('<p>前缀<strong>加粗词</strong>中段<em>斜体</em>尾部</p>');
      expect(blocks, hasLength(1));
      final b = blocks.single;
      expect(b.text, '前缀加粗词中段斜体尾部');
      expect(b.bold, [(2, 5)]);
      expect(b.text.substring(b.bold.single.$1, b.bold.single.$2), '加粗词');
      expect(b.italic, [(7, 9)]);
      expect(b.text.substring(b.italic.single.$1, b.italic.single.$2), '斜体');
    });

    test('插图独立成块并带 src', () {
      final blocks = htmlToBlocks(
          '<p>上文</p><img src="images/fig1.jpg" alt="图"/><p>下文</p>');
      expect(blocks, hasLength(3));
      expect(blocks[1].kind, ParaKind.image);
      expect(blocks[1].image, 'images/fig1.jpg');
      expect(blocks[1].text, '');
    });

    test('ChapterText.paragraphs 与 blocks 平行同长（旧接口兼容）', () {
      final blocks = htmlToBlocks('<h1>题</h1><img src="a.png"/><p>文</p>');
      final ch = ChapterText(
          title: 't',
          paragraphs: blocks.map((b) => b.text).toList(),
          blocks: blocks);
      expect(ch.paragraphs.length, ch.blocks.length);
      expect(ch.paragraphs[1], ''); // image 块在字符串层是空串
    });
  });

  group('分页引擎', () {
    const spec = PaginateSpec(
        width: 400, height: 600, fontSize: 18, lineHeight: 2.0);

    test('切片完整覆盖全部文本、无重叠、保持顺序', () {
      final longPara = '这是一句会重复很多次的话，用来撑出跨页长段落。' * 60; // ~1500 字
      final ch = ChapterText(title: 't', paragraphs: [
        '第一段短文。',
        longPara,
        '最后一段。',
      ]);
      final pages = paginateChapter(ch, spec);
      expect(pages.length, greaterThan(1), reason: '1500 字必然多页');

      // 重建文本：每段的切片拼回去必须等于原文
      final rebuilt = <int, StringBuffer>{};
      var lastPara = -1;
      var lastEnd = 0;
      for (final page in pages) {
        for (final s in page.slices) {
          if (s.para == lastPara) {
            expect(s.start, lastEnd, reason: '同段切片必须首尾相接');
          } else {
            expect(s.para, greaterThan(lastPara), reason: '段落顺序单调');
            expect(s.start, 0);
          }
          rebuilt
              .putIfAbsent(s.para, StringBuffer.new)
              .write(ch.paragraphs[s.para].substring(s.start, s.end));
          lastPara = s.para;
          lastEnd = s.end;
        }
      }
      for (var i = 0; i < ch.paragraphs.length; i++) {
        expect(rebuilt[i]?.toString(), ch.paragraphs[i],
            reason: '第 $i 段必须被完整分配');
      }
    });

    test('pageForParagraph 定位到包含该段的页', () {
      final ch = ChapterText(
          title: 't',
          paragraphs: List.generate(40, (i) => '第 $i 段：${'内容' * 30}'));
      final pages = paginateChapter(ch, spec);
      final p = pageForParagraph(pages, 39);
      expect(pages[p].slices.any((s) => s.para == 39), isTrue);
      expect(pageForParagraph(pages, 0), 0);
    });

    test('图片块占位不丢失', () {
      final blocks = [
        ParaBlock(text: '文字段落' * 10),
        ParaBlock(text: '', kind: ParaKind.image, image: 'a.jpg'),
        ParaBlock(text: '后续文字' * 10),
      ];
      final ch = ChapterText(
          title: 't',
          paragraphs: blocks.map((b) => b.text).toList(),
          blocks: blocks);
      final pages = paginateChapter(ch, spec);
      final allSlices = pages.expand((p) => p.slices).toList();
      expect(allSlices.any((s) => s.para == 1), isTrue, reason: '图片块必须出现');
    });
  });
}
