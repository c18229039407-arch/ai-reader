import 'package:ai_reader/ui/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('动效基建（ReactBits 范式的 Flutter 移植）', () {
    testWidgets('Reveal 动画完成后子组件完全可见', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Reveal(child: Text('hello'))),
      ));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('hello'), findsOneWidget);
      final opacity = tester.widget<Opacity>(find
          .ancestor(of: find.text('hello'), matching: find.byType(Opacity))
          .first);
      expect(opacity.opacity, 1.0);
    });

    testWidgets('系统减弱动效时 Reveal 直出终态（无动画帧）', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
              body: Reveal(
                  delay: Duration(seconds: 5), child: Text('instant'))),
        ),
      ));
      await tester.pump(); // 只泵一帧，不等 5 秒 delay
      final opacity = tester.widget<Opacity>(find
          .ancestor(of: find.text('instant'), matching: find.byType(Opacity))
          .first);
      expect(opacity.opacity, 1.0, reason: '减弱动效下不应有渐显过程');
    });

    testWidgets('CountUp 滚动到最终值', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CountUp(value: 120, format: (v) => '${v.round()} 分钟'),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('120 分钟'), findsOneWidget);
    });

    testWidgets('CountUp 减弱动效时直接显示终值', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: CountUp(value: 99, format: (v) => '${v.round()}'),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('99'), findsOneWidget);
    });

    test('staggerDelay 有步长且封顶', () {
      expect(staggerDelay(0), Duration.zero);
      expect(staggerDelay(3), const Duration(milliseconds: 210));
      expect(staggerDelay(99), const Duration(milliseconds: 700),
          reason: '默认封顶 10 步，长列表后段不无限等待');
    });
  });
}
