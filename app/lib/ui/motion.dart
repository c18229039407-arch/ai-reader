import 'dart:ui';

import 'package:flutter/material.dart';

/// 动效基建（借鉴 ReactBits 的 BlurText / SplitText / CountUp 范式，
/// Flutter 原生实现；遵循 UI Skills 的可访问性原则：
/// 系统开启「减弱动态效果」时直接呈现终态，不播动画）。
///
/// 调性约束（docs/design-system.md）：动效只出现在状态变化时，
/// 150–450ms，easeOutCubic 系，无循环、无纯装饰动画。

bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// 入场渐显：透明度 + 轻微上移 + 可选模糊消散（BlurText 范式）。
/// [delay] 用于交错（stagger）。
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 400),
    this.offsetY = 12,
    this.blur = 0,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;

  /// 初始模糊半径（0 = 不用模糊，纯位移渐显）。
  final double blur;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final CurvedAnimation _anim =
      CurvedAnimation(parent: _ctrl, curve: const Cubic(0.16, 1, 0.3, 1));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _ctrl.value = 1;
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      child: widget.child,
      builder: (context, child) {
        final v = _anim.value;
        Widget w = Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, widget.offsetY * (1 - v)),
            child: child,
          ),
        );
        if (widget.blur > 0 && v < 1) {
          final sigma = widget.blur * (1 - v);
          w = ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: w,
          );
        }
        return w;
      },
    );
  }
}

/// 交错入场的延迟：第 [index] 个元素延迟 index * [step]（默认 70ms，
/// 上限 [maxSteps] 避免长列表后段等待过久）。
Duration staggerDelay(int index, {int stepMs = 70, int maxSteps = 10}) =>
    Duration(milliseconds: (index.clamp(0, maxSteps)) * stepMs);

/// 数字滚动（CountUp 范式）：从 0 滚到 [value]，格式化交给 [format]。
class CountUp extends StatelessWidget {
  const CountUp({
    super.key,
    required this.value,
    required this.format,
    this.duration = const Duration(milliseconds: 700),
    this.style,
  });

  final num value;
  final String Function(num v) format;
  final Duration duration;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context) || value == 0) {
      return Text(format(value), style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(format(v), style: style),
    );
  }
}
