import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'epub_loader.dart';
import 'ollama_client.dart';
import 'reader_screen.dart';

void main() {
  runApp(const SpikeApp());
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Reader Spike',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _urlController = TextEditingController();
  final _occupationController = TextEditingController();
  List<String> _models = [];
  String? _model;
  bool? _healthy;
  bool _loadingBook = false;

  static String get _defaultUrl {
    // macOS 桌面默认本机；Android 需要手动填 Mac 的局域网 IP。
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://192.168.1.100:11434';
    }
    return 'http://127.0.0.1:11434';
  }

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    _urlController.text = prefs.getString('ollama_url') ?? _defaultUrl;
    _occupationController.text = prefs.getString('occupation') ?? '';
    _model = prefs.getString('model');
    setState(() {});
    _check();
  }

  Future<void> _check() async {
    final url = _urlController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ollama_url', url);
    await prefs.setString('occupation', _occupationController.text.trim());
    setState(() => _healthy = null);
    final client = OllamaClient(url);
    final ok = await client.healthCheck();
    List<String> models = [];
    if (ok) {
      try {
        models = await client.listModels();
      } catch (_) {}
    }
    setState(() {
      _healthy = ok;
      _models = models;
      if (_model == null || !models.contains(_model)) {
        _model = models.isNotEmpty ? models.first : null;
      }
    });
    if (_model != null) await prefs.setString('model', _model!);
  }

  Future<void> _openBook() async {
    if (_healthy != true || _model == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先确保 Ollama 连接正常并选好模型，再打开书。')),
      );
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
      withData: true, // 直接拿字节，桌面与移动行为一致
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;

    setState(() => _loadingBook = true);
    try {
      final book = await loadEpub(bytes);
      if (!mounted) return;
      if (book.chapters.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('解析成功但没有可显示的章节（记录到验收表）')));
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            book: book,
            ollamaUrl: _urlController.text.trim(),
            model: _model!,
            occupation: _occupationController.text.trim(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('EPUB 解析失败：$e')));
    } finally {
      if (mounted) setState(() => _loadingBook = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (_healthy) {
      true => Colors.green,
      false => Colors.red,
      null => Colors.orange,
    };
    final statusText = switch (_healthy) {
      true => 'Ollama 已连接（${_models.length} 个模型）',
      false => '连不上 Ollama——检查地址 / 局域网监听设置',
      null => '检测中…',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('AI Reader — Phase 0 Spike')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                '1. 连接 Ollama',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Ollama 地址',
                  helperText: 'Mac 本机默认即可；Android 填 Mac 的局域网 IP',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _check(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.circle, size: 12, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(child: Text(statusText)),
                  TextButton(onPressed: _check, child: const Text('重新检测')),
                ],
              ),
              if (_models.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _model,
                  decoration: const InputDecoration(
                    labelText: '模型',
                    border: OutlineInputBorder(),
                  ),
                  items: _models
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) async {
                    setState(() => _model = v);
                    final prefs = await SharedPreferences.getInstance();
                    if (v != null) await prefs.setString('model', v);
                  },
                ),
              ],
              const SizedBox(height: 24),
              Text(
                '2. 你的画像（用于个性化类比）',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _occupationController,
                decoration: const InputDecoration(
                  labelText: '职业 / 背景（如：产品经理，平时爱做饭）',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _check(),
              ),
              const SizedBox(height: 24),
              Text(
                '3. 打开一本 EPUB',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _loadingBook ? null : _openBook,
                icon: _loadingBook
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.menu_book),
                label: Text(_loadingBook ? '解析中…' : '选择 EPUB 文件'),
              ),
              const SizedBox(height: 12),
              Text(
                '验收动作：打开书 → 划选一段 → 右键/长按 → 「AI 解释」，'
                '观察解释是否贴合你填的画像，并记录面板右上角的首字延迟。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
