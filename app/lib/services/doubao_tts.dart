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

  /// 官方授权音色精选（大模型音色，均为平台正版授权声音）。
  static const presetVoices = <(String code, String label)>[
    ('zh_female_shuangkuaisisi_moon_bigtts', '爽快思思（女）'),
    ('zh_female_wanwanxiaohe_moon_bigtts', '湾湾小何（女）'),
    ('zh_female_linjianvhai_moon_bigtts', '邻家女孩（女）'),
    ('zh_male_yuanboxiaoshu_moon_bigtts', '渊博小叔（男）'),
    ('zh_male_beijingxiaoye_moon_bigtts', '北京小爷（男）'),
    ('zh_female_wenrouxiaoya_moon_bigtts', '温柔小雅（女）'),
  ];

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
    if (res.statusCode != 200) {
      throw Exception('豆包语音 HTTP ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final code = (data['code'] as num?)?.toInt();
    if (code != 3000) {
      throw Exception('豆包语音错误 $code：${data['message'] ?? '未知'}'
          '${code == 3001 ? '（检查 AppID/Token 是否正确、服务是否开通）' : ''}');
    }
    final b64 = data['data'] as String?;
    if (b64 == null || b64.isEmpty) {
      throw Exception('豆包语音返回空音频');
    }
    return base64Decode(b64);
  }
}
