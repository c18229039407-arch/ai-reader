import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import 'doubao_tts.dart';

/// 朗读服务：逐段 TTS，播完自动推进；音色/语速/音调/定时关闭。
/// 双引擎：系统 TTS（免费默认）/ 豆包语音大模型（BYO Key，官方授权音色）。
class TtsService {
  TtsService();

  final FlutterTts _tts = FlutterTts();
  bool _inited = false;

  // —— 豆包云端引擎 ——
  DoubaoTtsClient? _doubao;
  AudioPlayer? _player; // 惰性创建（测试环境无插件实现）
  StreamSubscription<void>? _playerDone;
  int _cloudSeq = 0; // 防过期回调（切段/停止后旧音频不再推进）

  AudioPlayer _ensurePlayer() {
    final p = _player ??= AudioPlayer();
    _playerDone ??= p.onPlayerComplete.listen((_) => _onSegmentDone());
    return p;
  }

  bool get usingCloud => _doubao != null;

  /// 配置豆包引擎；传 null 切回系统 TTS。
  void configureDoubao(
      {String? appId, String? token, String? voice}) {
    if (appId == null || appId.isEmpty || token == null || token.isEmpty) {
      _doubao = null;
      return;
    }
    _doubao = DoubaoTtsClient(
      appId: appId,
      accessToken: token,
      voiceType: (voice == null || voice.isEmpty)
          ? DoubaoTtsClient.defaultVoice
          : voice,
    );
  }

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
    final doubao = _doubao;
    if (doubao != null) {
      // 云端：合成 mp3 → 临时文件 → 播放（完成事件推进下一段）
      final seq = ++_cloudSeq;
      try {
        final mp3 = await doubao.synthesize(text,
            speed: (rate * 2).clamp(0.5, 2.0), pitch: pitch);
        if (!playing.value || seq != _cloudSeq) return; // 已停/已切段
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/linjian_tts_${seq % 4}.mp3');
        await f.writeAsBytes(mp3);
        await _ensurePlayer().play(DeviceFileSource(f.path));
      } catch (e) {
        debugPrint('豆包 TTS: $e');
        lastError.value = '$e';
        await stop();
      }
      return;
    }
    await _tts.speak(text);
  }

  /// 云端引擎最近一次错误（UI 展示用）。
  final ValueNotifier<String?> lastError = ValueNotifier(null);

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
    _cloudSeq++;
    await _tts.stop();
    await _player?.stop();
  }

  Future<void> resume() async {
    if (playing.value) return;
    playing.value = true;
    await _speakCurrent();
  }

  Future<void> stop() async {
    playing.value = false;
    currentPara.value = -1;
    _cloudSeq++;
    await _tts.stop();
    await _player?.stop();
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
    _playerDone?.cancel();
    _player?.dispose();
    currentPara.dispose();
    playing.dispose();
    sleepRemaining.dispose();
    lastError.dispose();
  }
}
