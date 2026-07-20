import 'package:ai_reader/screens/reader/share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('书摘分享卡片', () {
    test('三款主题齐全', () {
      expect(shareCardThemes.map((t) => t.name),
          ['暖纸', '夜墨', '松绿']);
    });

    testWidgets('卡片渲染出摘录、书名、作者、品牌署名', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ShareCard(
            quote: '真正的阅读障碍常发生在理解层。',
            bookTitle: '林间试读',
            author: '测试作者',
            theme: shareCardThemes.first,
          ),
        ),
      ));
      expect(find.textContaining('真正的阅读障碍'), findsOneWidget);
      expect(find.text('《林间试读》'), findsOneWidget);
      expect(find.text('测试作者'), findsOneWidget);
      expect(find.text('林间阅读'), findsOneWidget);
    });

    testWidgets('RepaintBoundary 可截图为非空图像', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: ShareCard(
              quote: '短句。',
              bookTitle: '书',
              author: '未知作者',
              theme: shareCardThemes[1],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      expect(image.width, greaterThan(0));
      expect(image.height, greaterThan(0));
    });

    testWidgets('未知作者时不显示作者行', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ShareCard(
            quote: 'q',
            bookTitle: 'b',
            author: '未知作者',
            theme: shareCardThemes.first,
          ),
        ),
      ));
      expect(find.text('未知作者'), findsNothing);
    });
  });
}
