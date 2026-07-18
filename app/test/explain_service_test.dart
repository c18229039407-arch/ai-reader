import 'package:flutter_test/flutter_test.dart';

import 'package:ai_reader/models/models.dart';
import 'package:ai_reader/services/epub_loader.dart';
import 'package:ai_reader/services/explain_service.dart';

void main() {
  final chapter = ChapterText(title: '论分工', paragraphs: [
    '段落0',
    '段落1',
    '段落2（选中在此）',
    '段落3',
    '段落4',
    '段落5',
  ]);

  test('buildContext 取前后各 2 段', () {
    final ctx = ExplainService.buildContext(chapter, 2, '选中文本');
    expect(ctx, contains('段落0'));
    expect(ctx, contains('段落4'));
    expect(ctx, isNot(contains('段落5')));
  });

  test('buildContext 边界：首段不越界', () {
    final ctx = ExplainService.buildContext(chapter, 0, 'x');
    expect(ctx, contains('段落0'));
    expect(ctx, contains('段落2'));
    expect(ctx, isNot(contains('段落3')));
  });

  test('explainSystem 注入书名/章节/上下文/画像', () {
    final sys = ExplainService.explainSystem(
      bookTitle: '国富论',
      chapterTitle: '论分工',
      contextExcerpt: 'CTX',
      profile: UserProfile(occupation: '程序员', personalizeOn: true),
    );
    expect(sys, contains('《国富论》'));
    expect(sys, contains('论分工'));
    expect(sys, contains('CTX'));
    expect(sys, contains('程序员'));
    expect(sys, contains('禁止用术语解释术语'));
  });

  test('关闭个性化后画像不进提示词', () {
    final sys = ExplainService.explainSystem(
      bookTitle: 'b',
      chapterTitle: 'c',
      contextExcerpt: 'x',
      profile: UserProfile(occupation: '程序员', personalizeOn: false),
    );
    expect(sys, isNot(contains('程序员')));
  });
}
