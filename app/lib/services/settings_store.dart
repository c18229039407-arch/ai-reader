import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// 应用设置（F1/F2/F3 + D7 画像 + C2/C3 排版偏好）。
/// 注意：MVP 使用 shared_preferences 存 Ollama 地址等配置；
/// 若未来接入云 API Key，须改存系统 Keychain（PRD F1），不得落明文。
class SettingsStore extends ChangeNotifier {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<SettingsStore> load() async =>
      SettingsStore(await SharedPreferences.getInstance());

  // ---------- 设备标识（E4）----------
  String get deviceId {
    var id = _prefs.getString('device_id');
    if (id == null || id.isEmpty) {
      id =
          'd${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${identityHashCode(this).toRadixString(36)}';
      _prefs.setString('device_id', id);
    }
    return id;
  }

  // ---------- AI（F1）----------
  String get ollamaUrl =>
      _prefs.getString('ollama_url') ?? 'http://127.0.0.1:11434';
  set ollamaUrl(String v) {
    _prefs.setString('ollama_url', v.trim());
    notifyListeners();
  }

  String get model => _prefs.getString('model') ?? '';
  set model(String v) {
    _prefs.setString('model', v);
    notifyListeners();
  }

  /// AI 总开关（F2）：关闭后阅读器不出现 AI 入口，也不发起任何外部请求。
  bool get aiEnabled => _prefs.getBool('ai_enabled') ?? true;
  set aiEnabled(bool v) {
    _prefs.setBool('ai_enabled', v);
    notifyListeners();
  }

  /// 首次隐私说明是否已确认（F3）。
  /// 封面提取规则版本：升级规则后触发一次全量重提取（v2 起排除站标 logo）。
  int get coverRev => _prefs.getInt('cover_rev') ?? 1;
  set coverRev(int v) {
    _prefs.setInt('cover_rev', v);
  }

  bool get privacyAcknowledged => _prefs.getBool('privacy_ack') ?? false;
  set privacyAcknowledged(bool v) {
    _prefs.setBool('privacy_ack', v);
    notifyListeners();
  }

  /// AI 首次自动配置是否已完成（自动扫描本地模型 / 引导填 Key）。
  bool get aiSetupDone => _prefs.getBool('ai_setup_done') ?? false;
  set aiSetupDone(bool v) {
    _prefs.setBool('ai_setup_done', v);
    notifyListeners();
  }

  // ---------- 云端 API Provider（F1b 第二档）----------
  /// 'ollama'（本地，默认） | 'openai'（OpenAI 兼容云端：DeepSeek 等）
  String get providerType => _prefs.getString('provider_type') ?? 'ollama';
  set providerType(String v) {
    _prefs.setString('provider_type', v);
    notifyListeners();
  }

  String get openaiBaseUrl =>
      _prefs.getString('openai_base_url') ?? 'https://api.deepseek.com';
  set openaiBaseUrl(String v) {
    _prefs.setString('openai_base_url', v.trim());
    notifyListeners();
  }

  String get openaiModel => _prefs.getString('openai_model') ?? 'deepseek-chat';
  set openaiModel(String v) {
    _prefs.setString('openai_model', v.trim());
    notifyListeners();
  }

  /// ⚠️ Alpha 版偏差：密钥暂存本地偏好文件（明文）。未签名分发的 App 使用系统
  /// 钥匙串存在权限问题，正式签名版将迁移至 Keychain/Keystore（PRD F1）。
  String get openaiApiKey => _prefs.getString('openai_api_key') ?? '';
  set openaiApiKey(String v) {
    _prefs.setString('openai_api_key', v.trim());
    notifyListeners();
  }

  /// 首次启动欢迎页是否已完成。
  bool get onboardingDone => _prefs.getBool('onboarding_done') ?? false;
  set onboardingDone(bool v) {
    _prefs.setBool('onboarding_done', v);
    notifyListeners();
  }

  /// 书源网络代理：'auto' 自动探测本机常见代理端口；'' 禁用；'host:port' 指定。
  String get proxyAddress => _prefs.getString('proxy_address') ?? 'auto';
  set proxyAddress(String v) {
    _prefs.setString('proxy_address', v.trim());
    notifyListeners();
  }

  // ---------- 自定义数据源（A5，实验性）----------
  /// 每行一个 Gutendex 兼容源的 baseUrl；添加何种源属用户自身行为。
  List<String> get customSourceUrls =>
      _prefs.getStringList('custom_sources') ?? [];
  set customSourceUrls(List<String> v) {
    _prefs.setStringList(
        'custom_sources', v.where((s) => s.trim().isNotEmpty).toList());
    notifyListeners();
  }

  // ---------- 画像（D7）----------
  UserProfile get profile => UserProfile(
        occupation: _prefs.getString('profile_occupation') ?? '',
        interests: _prefs.getString('profile_interests') ?? '',
        freeDescription: _prefs.getString('profile_free') ?? '',
        personalizeOn: _prefs.getBool('profile_personalize') ?? true,
      );

  void saveProfile(UserProfile p) {
    _prefs.setString('profile_occupation', p.occupation);
    _prefs.setString('profile_interests', p.interests);
    _prefs.setString('profile_free', p.freeDescription);
    _prefs.setBool('profile_personalize', p.personalizeOn);
    notifyListeners();
  }

  // ---------- 排版与主题（C2/C3）----------
  double get fontSize => _prefs.getDouble('font_size') ?? 18;
  set fontSize(double v) {
    _prefs.setDouble('font_size', v);
    notifyListeners();
  }

  double get lineHeight => _prefs.getDouble('line_height') ?? 2.0;
  set lineHeight(double v) {
    _prefs.setDouble('line_height', v);
    notifyListeners();
  }

  /// 阅读模式：scroll（上下滚动，默认）| page（左右翻页）。
  String get readingMode => _prefs.getString('reading_mode') ?? 'scroll';
  set readingMode(String v) {
    _prefs.setString('reading_mode', v);
  }

  /// 字间距（px）。
  double get letterSpacing => _prefs.getDouble('letter_spacing') ?? 0.2;
  set letterSpacing(double v) {
    _prefs.setDouble('letter_spacing', v);
    notifyListeners();
  }

  /// 段间距（px）。
  double get paraSpacing => _prefs.getDouble('para_spacing') ?? 14;
  set paraSpacing(double v) {
    _prefs.setDouble('para_spacing', v);
    notifyListeners();
  }

  /// 中文首行缩进两字。
  bool get firstLineIndent => _prefs.getBool('first_line_indent') ?? false;
  set firstLineIndent(bool v) {
    _prefs.setBool('first_line_indent', v);
    notifyListeners();
  }

  double get pageMargin => _prefs.getDouble('page_margin') ?? 28;
  set pageMargin(double v) {
    _prefs.setDouble('page_margin', v);
    notifyListeners();
  }

  /// 阅读纸张：索引对应 reader_papers.dart 的 readerPapers（0 = 跟随系统）
  int get readerTheme => _prefs.getInt('reader_theme') ?? 0;
  set readerTheme(int v) {
    _prefs.setInt('reader_theme', v);
    notifyListeners();
  }
}
