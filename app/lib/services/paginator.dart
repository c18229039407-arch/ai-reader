import 'package:flutter/rendering.dart';

import 'epub_loader.dart';

/// 一页中的一个切片：第 [para] 段的 [start, end) 子串。
/// 整段完整放入时 start=0, end=text.length。
class PageSlice {
  const PageSlice(this.para, this.start, this.end);

  final int para;
  final int start;
  final int end;
}

/// 一页。
class BookPage {
  const BookPage(this.slices);

  final List<PageSlice> slices;

  int get firstPara => slices.isEmpty ? 0 : slices.first.para;
}

/// 分页参数（同参数命中缓存）。
class PaginateSpec {
  const PaginateSpec({
    required this.width,
    required this.height,
    required this.fontSize,
    required this.lineHeight,
    this.paraSpacing = 14,
    this.imageHeight = 320,
  });

  final double width;
  final double height;
  final double fontSize;
  final double lineHeight;
  final double paraSpacing;
  final double imageHeight;

  @override
  bool operator ==(Object other) =>
      other is PaginateSpec &&
      other.width == width &&
      other.height == height &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight;

  @override
  int get hashCode => Object.hash(width, height, fontSize, lineHeight);
}

TextStyle _styleFor(ParaKind kind, PaginateSpec spec) {
  switch (kind) {
    case ParaKind.h1:
      return TextStyle(
          fontSize: spec.fontSize + 8,
          height: 1.4,
          fontWeight: FontWeight.w600);
    case ParaKind.h2:
      return TextStyle(
          fontSize: spec.fontSize + 5,
          height: 1.4,
          fontWeight: FontWeight.w600);
    case ParaKind.h3:
      return TextStyle(
          fontSize: spec.fontSize + 3,
          height: 1.4,
          fontWeight: FontWeight.w600);
    default:
      return TextStyle(fontSize: spec.fontSize, height: spec.lineHeight);
  }
}

/// 把一章按视口尺寸切成页。
///
/// 策略：段落整体装填；装不下的长段按 TextPainter 行度量在行边界切开。
/// 加粗对中文字宽无影响、西文影响 < 2%，测量统一用基准字重（工程取舍）。
List<BookPage> paginateChapter(ChapterText chapter, PaginateSpec spec) {
  final pages = <BookPage>[];
  var current = <PageSlice>[];
  var used = 0.0;

  void closePage() {
    if (current.isNotEmpty) {
      pages.add(BookPage(current));
      current = [];
      used = 0.0;
    }
  }

  double measure(String text, ParaKind kind) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: _styleFor(kind, spec)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: spec.width);
    final h = tp.height;
    tp.dispose();
    return h;
  }

  for (var i = 0; i < chapter.blocks.length; i++) {
    final block = chapter.blocks[i];

    if (block.kind == ParaKind.image) {
      final need = spec.imageHeight + spec.paraSpacing;
      if (used + need > spec.height && current.isNotEmpty) closePage();
      current.add(PageSlice(i, 0, 0));
      used += need;
      continue;
    }
    if (block.text.isEmpty) continue;

    var start = 0;
    while (start < block.text.length) {
      final remainText = block.text.substring(start);
      final blockH = measure(remainText, block.kind);
      final avail = spec.height - used;

      if (blockH + spec.paraSpacing <= avail) {
        // 整体放得下
        current.add(PageSlice(i, start, block.text.length));
        used += blockH + spec.paraSpacing;
        start = block.text.length;
        continue;
      }

      // 放不下：按行切
      final tp = TextPainter(
        text: TextSpan(text: remainText, style: _styleFor(block.kind, spec)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: spec.width);
      final lines = tp.computeLineMetrics();
      var fitH = 0.0;
      var fitLines = 0;
      for (final lm in lines) {
        if (fitH + lm.height > avail) break;
        fitH += lm.height;
        fitLines++;
      }
      if (fitLines == 0) {
        tp.dispose();
        if (current.isEmpty) {
          // 单行都放不下（视口过小）：硬塞一行避免死循环
          final cut = tp.text!.toPlainText().length.clamp(1, remainText.length);
          current.add(PageSlice(i, start, start + cut));
          start += cut;
        }
        closePage();
        continue;
      }
      // 第 fitLines 行末的字符偏移
      final cutPos = tp
          .getPositionForOffset(Offset(spec.width, fitH - 0.5))
          .offset
          .clamp(1, remainText.length);
      tp.dispose();
      current.add(PageSlice(i, start, start + cutPos));
      start += cutPos;
      closePage();
    }
  }
  closePage();
  if (pages.isEmpty) pages.add(const BookPage([]));
  return pages;
}

/// 找到包含指定段落的页码（用于恢复进度 / 概念本回跳）。
int pageForParagraph(List<BookPage> pages, int para) {
  for (var i = 0; i < pages.length; i++) {
    for (final s in pages[i].slices) {
      if (s.para == para) return i;
    }
  }
  return 0;
}
