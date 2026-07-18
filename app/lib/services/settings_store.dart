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
  bool get privacyAcknowledged => _prefs.getBool('privacy_ack') ?? false;
  set privacyAcknowledged(bool v) {
    _prefs.setBool('privacy_ack', v);
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
  double get fontSize => _prefs.getDouble('font_size') ?? 17;
  set fontSize(double v) {
    _prefs.setDouble('font_size', v);
    notifyListeners();
  }

  double get lineHeight => _prefs.getDouble('line_height') ?? 1.9;
  set lineHeight(double v) {
    _prefs.setDouble('line_height', v);
    notifyListeners();
  }

  double get pageMargin => _prefs.getDouble('page_margin') ?? 28;
  set pageMargin(double v) {
    _prefs.setDouble('page_margin', v);
    notifyListeners();
  }

  /// 阅读主题：0 跟随系统 / 1 日间 / 2 夜间 / 3 护眼纸质
  int get readerTheme => _prefs.getInt('reader_theme') ?? 0;
  set readerTheme(int v) {
    _prefs.setInt('reader_theme', v);
    notifyListeners();
  }
}
