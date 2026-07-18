import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_reader_spike/epub_loader.dart';
import 'package:ai_reader_spike/main.dart';
import 'package:ai_reader_spike/reader_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('首页冒烟：三步引导与关键控件都在', (tester) async {
    await tester.pumpWidget(const SpikeApp());
    await tester.pump(); // 首帧

    expect(find.text('1. 连接 Ollama'), findsOneWidget);
    expect(find.text('2. 你的画像（用于个性化类比）'), findsOneWidget);
    expect(find.text('3. 打开一本 EPUB'), findsOneWidget);
    expect(find.text('选择 EPUB 文件'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('阅读页冒烟：章节渲染、SelectionArea、翻章', (tester) async {
    final book = LoadedBook(
      title: '测试书',
      author: '测试作者',
      chapters: [
        ChapterText(title: '第一章', paragraphs: ['第一段内容。', '第二段内容。']),
        ChapterText(title: '第二章', paragraphs: ['第二章的内容。']),
      ],
    );

    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(
        book: book,
        ollamaUrl: 'http://127.0.0.1:11434',
        model: 'test-model',
        occupation: '测试职业',
      ),
    ));

    // 正文渲染
    expect(find.text('第一段内容。'), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);

    // 翻到下一章
    await tester.tap(find.byTooltip('下一章'));
    await tester.pumpAndSettle();
    expect(find.text('第二章的内容。'), findsOneWidget);
    expect(find.text('第一段内容。'), findsNothing);

    // 末章时「下一章」按钮应禁用
    final nextBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right));
    expect(nextBtn.onPressed, isNull);
  });
}
