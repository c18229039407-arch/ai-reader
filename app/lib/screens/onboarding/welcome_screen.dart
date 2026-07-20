import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/ai_autodetect.dart';
import '../../services/library_store.dart';
import '../../services/settings_store.dart';
import '../shelf/shelf_screen.dart';

/// 首次启动欢迎页：品牌 → 画像 → AI 就绪，三步一次性完成。
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.settings, required this.store});

  final SettingsStore settings;
  final LibraryStore store;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _page = PageController();
  int _step = 0;

  final _occupation = TextEditingController();
  final _interests = TextEditingController();
  final _apiKey = TextEditingController();

  // AI 探测状态：null=进行中，''=未找到本地模型，其他=成功文案
  String? _aiResult;
  bool _detecting = false;

  @override
  void dispose() {
    _page.dispose();
    _occupation.dispose();
    _interests.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == 1) {
      widget.settings.saveProfile(UserProfile(
        occupation: _occupation.text,
        interests: _interests.text,
        personalizeOn: true,
      ));
      _startDetect();
    }
    setState(() => _step += 1);
    _page.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic);
  }

  Future<void> _startDetect() async {
    if (_detecting) return;
    _detecting = true;
    final msg = await autoDetectLocalAi(widget.settings);
    if (mounted) setState(() => _aiResult = msg ?? '');
  }

  void _finish() {
    final key = _apiKey.text.trim();
    if (key.isNotEmpty) {
      widget.settings
        ..providerType = 'openai'
        ..openaiBaseUrl = 'https://api.deepseek.com'
        ..openaiModel = 'deepseek-chat'
        ..openaiApiKey = key;
    }
    widget.settings
      ..privacyAcknowledged = true
      ..aiSetupDone = true
      ..onboardingDone = true;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) =>
            ShelfScreen(settings: widget.settings, store: widget.store)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const serif = ['Songti SC', 'STSong', 'Noto Serif SC', 'serif'];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _page,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      // —— 第 1 步：品牌与承诺 ——
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: Image.asset('assets/icon/logo.png',
                                  width: 96, height: 96),
                            ),
                            const SizedBox(height: 24),
                            const Text('林间阅读',
                                style: TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w600,
                                    fontFamilyFallback: serif)),
                            const SizedBox(height: 12),
                            Text('读到看不懂的地方，\nAI 用你熟悉的生活经验讲给你听。',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 15,
                                    height: 1.8,
                                    color: scheme.onSurfaceVariant)),
                            const SizedBox(height: 28),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest
                                    .withValues(alpha: .4),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '你的书籍与全部阅读数据只存在本机，无账号、无云端、无上报。'
                                '仅在你主动使用 AI 时，所选文字会发送给你配置的 AI 服务。',
                                style: TextStyle(
                                    fontSize: 12,
                                    height: 1.7,
                                    color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // —— 第 2 步：画像 ——
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('先认识一下你',
                                style: TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Text('AI 会用贴合你职业和爱好的例子来解释概念——\n填得越真，例子越像给你量身讲的。',
                                style: TextStyle(
                                    fontSize: 13,
                                    height: 1.7,
                                    color: scheme.onSurfaceVariant)),
                            const SizedBox(height: 24),
                            TextField(
                              controller: _occupation,
                              decoration: const InputDecoration(
                                  labelText: '你的职业',
                                  hintText: '如：产品经理 / 老师 / 程序员',
                                  border: OutlineInputBorder()),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _interests,
                              decoration: const InputDecoration(
                                  labelText: '兴趣爱好（逗号分隔）',
                                  hintText: '如：做饭, 骑行, 打游戏',
                                  border: OutlineInputBorder()),
                            ),
                          ],
                        ),
                      ),
                      // —— 第 3 步：AI 就绪 ——
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('接入 AI',
                                style: TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 20),
                            if (_aiResult == null)
                              Row(children: [
                                const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                                const SizedBox(width: 12),
                                Text('正在扫描本机模型服务…',
                                    style: TextStyle(
                                        color: scheme.onSurfaceVariant)),
                              ])
                            else if (_aiResult!.isNotEmpty)
                              Row(children: [
                                Icon(Icons.check_circle,
                                    color: scheme.primary, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text('$_aiResult\n零费用，开箱即用。',
                                        style: const TextStyle(height: 1.6))),
                              ])
                            else ...[
                              Text(
                                '没有检测到本机模型（Ollama / LM Studio）。\n'
                                '可以填一个 DeepSeek API Key 直接使用（platform.deepseek.com 注册，一次解释约几厘钱），也可以先跳过。',
                                style: TextStyle(
                                    fontSize: 13,
                                    height: 1.7,
                                    color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _apiKey,
                                obscureText: true,
                                decoration: const InputDecoration(
                                    labelText: 'DeepSeek API Key（可选）',
                                    border: OutlineInputBorder()),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // —— 步骤指示 + 按钮 ——
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
                  child: Row(
                    children: [
                      Row(
                        children: List.generate(
                          3,
                          (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 240),
                            margin: const EdgeInsets.only(right: 6),
                            width: i == _step ? 22 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _step
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (_step < 2)
                        FilledButton(
                            onPressed: _next,
                            child: Text(_step == 0 ? '开始' : '下一步'))
                      else
                        FilledButton(
                            onPressed: _finish, child: const Text('进入书架')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
