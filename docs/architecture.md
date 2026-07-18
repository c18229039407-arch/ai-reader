# 技术架构

> 与 PRD §6 对应，此处为面向实现的细化版。随代码演进持续更新。

## 1. 分层总览

```
┌─────────────────────────────────────────────┐
│  UI 层（Flutter，一套代码两套交互）              │
│   · macOS：分栏布局、快捷键、鼠标划选            │
│   · Android：沉浸阅读、长按划选、底部抽屉        │
├─────────────────────────────────────────────┤
│  应用逻辑层                                     │
│   · 书架管理   · 阅读器引擎   · 标注/进度         │
│   · Explain Orchestrator（解释编排器）          │
│   · Translation Pipeline（翻译管线）            │
│   · Source Adapters（数据源适配器）             │
├─────────────────────────────────────────────┤
│  本地数据层（SQLite + 应用目录文件）             │
├─────────────────────────────────────────────┤
│  外部依赖（按需、可关闭）                         │
│   · LLMProvider：Ollama(本机/局域网)/API        │
│   · 合法公版源 / Open Library 元数据             │
└─────────────────────────────────────────────┘
```

## 2. 核心接口（Dart 签名草案）

### 2.1 LLMProvider

```dart
abstract class LLMProvider {
  String get id;                      // 'ollama-local' | 'ollama-lan' | 'openai-compat' | 'anthropic'
  Future<bool> healthCheck();
  Stream<String> complete(LLMRequest req);   // 流式返回
}

class LLMRequest {
  final String system;
  final List<LLMMessage> messages;
  final double temperature;
  final int? maxTokens;
}
```

Provider 解析顺序（F1b）：

- macOS：`ollama-local` → 用户配置的 API
- Android：`ollama-lan`（可达性探测，超时 2s）→ 用户配置的 API →（P2）端上小模型

### 2.2 BookSource（数据源适配器）

```dart
abstract class BookSource {
  String get id;
  String get displayName;
  String get licenseNote;             // 该源内容的许可性质说明，UI 展示
  Future<List<BookSearchResult>> search(String query, {String? lang});
  Future<DownloadHandle> fetch(String bookId);  // 仅合法源实现下载
}
```

红线（与 CONTRIBUTING 一致）：仓库内只实现合法公版/授权源适配器。

### 2.3 Explain Orchestrator

一次「解释」调用的组装流程：

```
selection ──┐
context(±N段) ──┤
book meta ──┼──► PromptBuilder ──► LLMProvider.complete() ──► 解释卡片
user profile ──┤        ▲
depth/换例指令 ──┘        └── 模板要点：通俗语言；禁止以术语解释术语；
                              给一个贴合用户画像的例子；指出本书语境下的特定含义
```

### 2.4 Translation Pipeline（G2 批量翻译）

```
EPUB ──► 章节/段落切分（保留段落ID） ──► 任务队列（可暂停/断点续跑）
      ──► 逐段 LLMProvider 翻译 ──► 译文库（para_id ↔ 译文）
      ──► 产出：中文版 EPUB / 双语对照 EPUB → 入书架
```

## 3. 本地数据模型

```
Book(id, title, author, cover_path, file_path, format, source, license, lang, added_at)
ReadingState(book_id, locator, percent, updated_at, device_id)
Annotation(id, book_id, type[highlight|note|bookmark], locator, color, text, created_at, device_id)
Explanation(id, book_id, locator, term, context_excerpt, result_text, created_at)  -- locator: 正文锚点定位(D8)
Translation(book_id, para_id, source_text_hash, translated_text, provider, created_at)
UserProfile(occupation, interests[], analogy_domains[], free_description, default_depth, personalize_on)
Setting(llm_config, privacy_flags, sync_config)        // API Key 存系统 Keychain/Keystore，不落库
```

## 4. Syncthing 友好的数据布局

Syncthing 做的是文件夹同步，App 本身不实现同步协议。约定：

```
~/AIReader/                    ← Syncthing 同步根目录
  books/                       ← 书籍原文件（文件级同步，天然无冲突）
  covers/
  state/
    annotations.jsonl          ← 追加式标注日志（append-only，按 device_id+时间戳合并）
    reading_state.json         ← 各设备各写一份 reading_state.<device_id>.json，读取时取最新
  library.db                   ← 本机 SQLite（**不同步**，从 state/ 重建）
```

关键决策：**SQLite 文件不进同步目录**（二进制冲突不可合并），同步的是可合并的 JSON/JSONL 导出层，各端启动时将其合并进本机数据库。这是 Phase 2 的核心实现点。

## 5. Phase 0 验证项与通过标准

| # | 验证项 | 通过标准 |
|---|---|---|
| 1 | Flutter 双端骨架 | 同一工程在 macOS 窗口和安卓真机上都能启动并显示同一页面 |
| 2 | EPUB 渲染选型 | 候选库能打开 3 本不同来源的公版 EPUB：正确显示目录、翻页、中文排版不乱 |
| 3 | 本机 Ollama 链路 | macOS 端划选一段文字 → qwen2.5:7b 流式返回解释，首字 < 3s |
| 4 | 局域网 Ollama 链路 | 安卓端通过 `http://<Mac-IP>:11434` 完成同样的调用，测量延迟 |

任一项不达标 → 回到选型层重议（EPUB 库替换 / 模型换档 / 交互降级），不带病进入 Phase 1。
