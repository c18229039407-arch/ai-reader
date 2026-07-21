import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// 豆包语音大模型 TTS 客户端（火山引擎 openspeech，BYO Key）。
///
/// 合规约束：只使用平台官方授权音色库里的音色（voice_type），
/// 不提供、不接入任何针对真实人物的声音克隆——未经本人授权复刻他人声音
/// 侵犯《民法典》第 1023 条保护的声音权益（红线，同 CONTRIBUTING 数据源条款）。
class DoubaoTtsClient {
  DoubaoTtsClient({
    required this.appId,
    required this.accessToken,
    this.voiceType = defaultVoice,
    this.baseUrl = 'https://openspeech.bytedance.com',
    http.Client? client,
  }) : _http = client ?? http.Client();

  final String appId;
  final String accessToken;
  final String voiceType;
  final String baseUrl;
  final http.Client _http;

  static const defaultVoice = 'zh_female_shuangkuaisisi_moon_bigtts';

  /// 官方授权音色精选。两档：
  /// - 经典音色（BV 开头）：基础语音合成服务即可用，开通门槛最低（真实账号实测可用）
  /// - 大模型音色（_moon_bigtts）：需在控制台额外开通「语音合成大模型」
  static const presetVoices = <(String code, String label)>[
    ('BV700_streaming', '灿灿（女·经典）'),
    ('BV001_streaming', '通用女声（经典）'),
    ('BV002_streaming', '通用男声（经典）'),
    ('zh_female_wanwanxiaohe_moon_bigtts', '婉婉小荷（女·大模型）'),
    ('zh_female_shuangkuaisisi_moon_bigtts', '爽快思思（女·大模型）'),
    ('zh_male_wennuanahu_moon_bigtts', '温暖阿虎（男·大模型）'),
  ];

  /// 「清甜温柔」一键预设（按用户提供的豆包 APP 调音参数换算到 API 刻度）：
  /// 语速 0.90~0.98 → speed_ratio 0.94；音高 +0.4~+0.7（APP -1..+1 刻度）
  /// → pitch_ratio ≈ 1.25；音色取温柔女声 婉婉小荷。
  /// 注：APP 里的「混响 15%-25%」「情感调」为智能体界面功能，TTS API 不支持。
  static const sweetGentlePreset = (
    voice: 'zh_female_wanwanxiaohe_moon_bigtts',
    speedRatio: 0.94,
    pitchRatio: 1.25,
  );

  /// 清甜预设·经典版：未开通大模型服务时的即用替代（灿灿 + 同参数）。
  static const sweetClassicPreset = (
    voice: 'BV700_streaming',
    speedRatio: 0.94,
    pitchRatio: 1.25,
  );

  /// 一段式粘贴解析：用户把「AppID:Token」整段贴进来自动拆两项。
  /// 支持 冒号/分号/逗号/空白 分隔；AppID 是纯数字（火山控制台格式）。
  static (String appId, String token)? parseCombinedKey(String input) {
    final m = RegExp(r'^\s*(\d{6,16})\s*[:;,，；：\s]+\s*(\S{10,})\s*$')
        .firstMatch(input);
    if (m == null) return null;
    return (m.group(1)!, m.group(2)!);
  }

  /// 合成一段文本，返回 MP3 字节。[speed]/[pitch] 与系统 TTS 面板同刻度。
  Future<Uint8List> synthesize(String text,
      {double speed = 1.0, double pitch = 1.0}) async {
    final uri = Uri.parse('$baseUrl/api/v1/tts');
    final body = jsonEncode({
      'app': {'appid': appId, 'token': accessToken, 'cluster': 'volcano_tts'},
      'user': {'uid': 'linjian-reader'},
      'audio': {
        'voice_type': voiceType,
        'encoding': 'mp3',
        'speed_ratio': speed.clamp(0.5, 2.0),
        'pitch_ratio': pitch.clamp(0.5, 2.0),
      },
      'request': {
        'reqid': '${DateTime.now().microsecondsSinceEpoch}',
        'text': text,
        'operation': 'query',
      },
    });
    final res = await _http
        .post(uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer;$accessToken',
            },
            body: body)
        .timeout(const Duration(seconds: 30));

    // 注意：豆包出错时是「非 200 状态码 + JSON 错误体」（实测 401+code:3001），
    // 必须先解析 JSON 拿真实原因，不能只看 HTTP 状态码。
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      // 非 JSON 响应（网关错误等）
    }
    final code = (data?['code'] as num?)?.toInt();
    final message = data?['message']?.toString();

    if (res.statusCode != 200 || code != 3000) {
      throw Exception(describeError(code, message, res.statusCode));
    }
    final b64 = data?['data'] as String?;
    if (b64 == null || b64.isEmpty) {
      throw Exception('豆包语音返回空音频');
    }
    return base64Decode(b64);
  }

  /// 把豆包错误码翻译成用户能操作的中文提示。
  static String describeError(int? code, String? message, int httpStatus) {
    final raw = '（$code ${message ?? ''} HTTP $httpStatus）';
    if (code == 3001 || (message ?? '').contains('grant')) {
      if ((message ?? '').contains('10029')) {
        return '「语音合成大模型」服务未开通（大模型音色需要它）。'
            '两个解决办法：换用经典音色（灿灿/通用女声等 BV 开头，基础服务即用）；'
            '或到火山控制台「语音技术 → 语音合成大模型」开通并领免费额度。$raw';
      }
      return '服务未开通或音色未授权：到火山控制台「语音技术」确认服务已开通、'
          '所选音色已授权；Token 错误也会报这个。$raw';
    }
    if (code == 3003) {
      return '额度已用完或触发限流，稍后再试或到控制台充值。$raw';
    }
    if (code == 3005) {
      return '服务端繁忙，稍后重试。$raw';
    }
    if (code == 3011) {
      return '请求参数无效：多半是音色代码不存在或本账号未开通该音色，'
          '换预置音色或到控制台音色列表复制正确代码。$raw';
    }
    if (httpStatus == 401 || httpStatus == 403) {
      return '鉴权失败：检查 AppID 与 Access Token 是否复制完整、有无多余空格。$raw';
    }
    return '豆包语音调用失败。$raw';
  }
}
