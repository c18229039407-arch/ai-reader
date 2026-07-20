import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 朗读服务：逐段 TTS，播完自动推进；音色/语速/音调/定时关闭。
/// 真机发声由系统 TTS 引擎提供（macOS 内置、Android 需 TTS 引擎）。
class TtsService {
  TtsService();

  final FlutterTts _tts = FlutterTts();
  bool _inited = false;

  /// 当前朗读段落索引（-1 = 未在朗读）。
  final ValueNotifier<int> currentPara = ValueNotifier(-1);
  final ValueNotifier<bool> playing = ValueNotifier(false);

  /// 可用音色列表（name/locale）。
  List<Map<String, String>> voices = [];

  // 参数
  double rate = 0.5; // 0..1（flutter_tts 语速）
  double pitch = 1.0; // 0.5..2.0
  String? voiceName;

  // 朗读队列
  List<String> _paras = [];
  int _index = 0;
  VoidCallback? _onAdvance; // 通知 UI 当前段变化 / 章末续接
  Future<bool> Function()? _onChapterEnd; // 读完本章：返回 true 表示已续到下一章

  // 定时关闭
  Timer? _sleepTimer;
  final ValueNotifier<Duration?> sleepRemaining = ValueNotifier(null);
  Timer? _sleepTick;
  bool _stopAtChapterEnd = false;

  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    try {
      await _tts.awaitSpeakCompletion(true);
      final raw = await _tts.getVoices;
      voices = [
        for (final v in (raw as List? ?? []))
          if (v is Map)
            {
              'name': '${v['name'] ?? ''}',
              'locale': '${v['locale'] ?? ''}',
            }
      ];
      // 优先中文音色
      final zh = voices.firstWhere(
        (v) => v['locale']!.toLowerCase().startsWith('zh'),
        orElse: () => voices.isNotEmpty ? voices.first : {},
      );
      voiceName = zh['name'];
      if (voiceName != null && voiceName!.isNotEmpty) {
        await _tts.setVoice(
            {'name': voiceName!, 'locale': zh['locale'] ?? 'zh-CN'});
      } else {
        await _tts.setLanguage('zh-CN');
      }
    } catch (e) {
      debugPrint('TTS init: $e');
    }
    _tts.setCompletionHandler(_onSegmentDone);
  }

  Future<void> applyParams() async {
    await _tts.setSpeechRate(rate);
    await _tts.setPitch(pitch);
    if (voiceName != null && voiceName!.isNotEmpty) {
      final v = voices.firstWhere((e) => e['name'] == voiceName,
          orElse: () => {});
      await _tts.setVoice(
          {'name': voiceName!, 'locale': v['locale'] ?? 'zh-CN'});
    }
  }

  /// 从指定段开始朗读整章。
  Future<void> start(List<String> paras, int from,
      {VoidCallback? onAdvance,
      Future<bool> Function()? onChapterEnd}) async {
    await init();
    await applyParams();
    _paras = paras;
    _index = from.clamp(0, paras.isEmpty ? 0 : paras.length - 1);
    _onAdvance = onAdvance;
    _onChapterEnd = onChapterEnd;
    playing.value = true;
    await _speakCurrent();
  }

  Future<void> _speakCurrent() async {
    if (!playing.value) return;
    if (_index >= _paras.length) {
      // 章末
      if (_stopAtChapterEnd) {
        await stop();
        return;
      }
      final advanced = await _onChapterEnd?.call() ?? false;
      if (advanced) {
        _index = 0;
        if (_paras.isNotEmpty) {
          await _speakCurrent();
        }
      } else {
        await stop();
      }
      return;
    }
    currentPara.value = _index;
    _onAdvance?.call();
    final text = _paras[_index].trim();
    if (text.isEmpty) {
      _index++;
      await _speakCurrent();
      return;
    }
    await _tts.speak(text);
  }

  void _onSegmentDone() {
    if (!playing.value) return;
    _index++;
    _speakCurrent();
  }

  /// 更新队列（切章后由 UI 调用，保持朗读连续）。
  void updateParas(List<String> paras) {
    _paras = paras;
  }

  Future<void> pause() async {
    playing.value = false;
    await _tts.stop();
  }

  Future<void> resume() async {
    if (playing.value) return;
    playing.value = true;
    await _speakCurrent();
  }

  Future<void> stop() async {
    playing.value = false;
    currentPara.value = -1;
    await _tts.stop();
    _cancelSleep();
  }

  /// 定时关闭：分钟数（null=取消）；[atChapterEnd] 为读完本章后停。
  void setSleep({int? minutes, bool atChapterEnd = false}) {
    _cancelSleep();
    _stopAtChapterEnd = atChapterEnd;
    if (atChapterEnd) {
      sleepRemaining.value = null;
      return;
    }
    if (minutes == null) return;
    var remain = Duration(minutes: minutes);
    sleepRemaining.value = remain;
    _sleepTick = Timer.periodic(const Duration(seconds: 1), (_) {
      remain -= const Duration(seconds: 1);
      sleepRemaining.value = remain;
      if (remain <= Duration.zero) _cancelSleep();
    });
    _sleepTimer = Timer(Duration(minutes: minutes), stop);
  }

  void _cancelSleep() {
    _sleepTimer?.cancel();
    _sleepTick?.cancel();
    _sleepTimer = null;
    _sleepTick = null;
    _stopAtChapterEnd = false;
    sleepRemaining.value = null;
  }

  void dispose() {
    _cancelSleep();
    _tts.stop();
    currentPara.dispose();
    playing.dispose();
    sleepRemaining.dispose();
  }
}
