import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/library_store.dart';
import '../../services/ollama_client.dart';
import '../../services/settings_store.dart';

/// 设置页（F1/F1b/F2/F3 + D7 画像 + A5 自定义源 + B5 备份）。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings, this.store});

  final SettingsStore settings;
  final LibraryStore? store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;
  late final TextEditingController _occupation;
  late final TextEditingController _interests;
  late final TextEditingController _free;
  List<String> _models = [];
  bool? _healthy;

  SettingsStore get s => widget.settings;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: s.ollamaUrl);
    final p = s.profile;
    _occupation = TextEditingController(text: p.occupation);
    _interests = TextEditingController(text: p.interests);
    _free = TextEditingController(text: p.freeDescription);
    _check();
  }

  @override
  void dispose() {
    _url.dispose();
    _occupation.dispose();
    _interests.dispose();
    _free.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    s.ollamaUrl = _url.text.trim();
    setState(() => _healthy = null);
    final client = OllamaClient(s.ollamaUrl);
    final ok = await client.healthCheck();
    var models = <String>[];
    if (ok) {
      try {
        models = await client.listModels();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _healthy = ok;
      _models = models;
      if (models.isNotEmpty && !models.contains(s.model)) {
        s.model = models.first;
      }
    });
  }

  void _saveProfile() {
    s.saveProfile(UserProfile(
      occupation: _occupation.text,
      interests: _interests.text,
      freeDescription: _free.text,
      personalizeOn: s.profile.personalizeOn,
    ));
  }

  Future<void> _exportBundle() async {
    final json = await widget.store!.exportBundle();
    final bytes = Uint8List.fromList(utf8.encode(json));
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出 AI Reader 备份',
      fileName:
          'ai-reader-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );
    if (path != null) {
      final f = File(path);
      if (!await f.exists() || (await f.length()) == 0) {
        await f.writeAsString(json); // 桌面端 saveFile 只回路径时自行写入
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('备份已导出')));
      }
    }
  }

  Future<void> _importBundle() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    try {
      final added = await widget.store!.importBundle(utf8.decode(bytes));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入完成：新增 $added 本书目，阅读记录已合并')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (_healthy) {
      true => Colors.green,
      false => Theme.of(context).colorScheme.error,
      null => Colors.orange,
    };
    final statusText = switch (_healthy) {
      true => '已连接（${_models.length} 个模型）',
      false => '连不上——检查 Ollama 是否在运行、地址是否正确',
      null => '检测中…',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('AI 服务', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用 AI（解释 / 翻译）'),
                subtitle: const Text('关闭后应用不发起任何外部请求'),
                value: s.aiEnabled,
                onChanged: (v) => setState(() => s.aiEnabled = v),
              ),
              if (s.aiEnabled) ...[
                TextField(
                  controller: _url,
                  decoration: const InputDecoration(
                    labelText: 'Ollama 地址',
                    helperText: 'Mac 本机默认 http://127.0.0.1:11434',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _check(),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.circle, size: 12, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(child: Text(statusText)),
                  TextButton(onPressed: _check, child: const Text('重新检测')),
                ]),
                if (_models.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _models.contains(s.model) ? s.model : null,
                    decoration: const InputDecoration(
                        labelText: '模型', border: OutlineInputBorder()),
                    items: _models
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => s.model = v);
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '电脑卡顿？8GB 内存的 M1/M2 跑 7b 模型容易内存吃紧。'
                    '终端执行 ollama pull qwen2.5:3b（仅 1.9GB）后回来切换，流畅得多；'
                    '仍卡可再降 qwen2.5:1.5b。',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(height: 1.5),
                  ),
                ],
              ],
              const SizedBox(height: 28),
              Text('我的画像（用于个性化类比）',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用个性化'),
                subtitle: const Text('关闭后 AI 解释不参考画像'),
                value: s.profile.personalizeOn,
                onChanged: (v) {
                  final p = s.profile..personalizeOn = v;
                  s.saveProfile(p);
                  setState(() {});
                },
              ),
              TextField(
                controller: _occupation,
                decoration: const InputDecoration(
                    labelText: '职业', border: OutlineInputBorder()),
                onChanged: (_) => _saveProfile(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _interests,
                decoration: const InputDecoration(
                    labelText: '兴趣（逗号分隔）',
                    hintText: '做饭, 骑行, 打游戏',
                    border: OutlineInputBorder()),
                onChanged: (_) => _saveProfile(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _free,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: '自由描述（可选）',
                    hintText: '例如：最近在自学统计学；家里有猫；通勤坐地铁一小时…',
                    border: OutlineInputBorder()),
                onChanged: (_) => _saveProfile(),
              ),
              const SizedBox(height: 28),
              Text('自定义公版书源（实验，A5）',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller:
                    TextEditingController(text: s.customSourceUrls.join('\n')),
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: '每行一个 Gutendex 兼容源的地址（默认已含 gutendex.com）',
                  helperText: '自行添加的数据源，内容合规责任由你自负',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => s.customSourceUrls = v.split('\n'),
              ),
              if (widget.store != null) ...[
                const SizedBox(height: 28),
                Text('数据备份（B5）',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('导出/导入书架元数据与全部阅读记录（进度/高亮/笔记/解释）。不含书籍文件本体。',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Row(children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.upload_outlined, size: 18),
                    label: const Text('导出备份'),
                    onPressed: _exportBundle,
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('导入备份'),
                    onPressed: _importBundle,
                  ),
                ]),
              ],
              const SizedBox(height: 28),
              Text('隐私', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '所有书籍与阅读数据仅存本机。触发 AI 时，所选文字及其前后几段会发送给上方配置的服务'
                '（默认本机 Ollama，数据不出设备）。本应用无账号、无云端、无任何数据上报。',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(height: 1.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
