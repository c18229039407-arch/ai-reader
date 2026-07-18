# Phase 0 Spike：验证代码运行手册

对应 `docs/architecture.md` §5 的四条验证链路。前提：已完成 `docs/phase0-setup.md` 的环境搭建（四项核对清单全过）。

## 一、生成平台工程并运行（macOS）

本目录只包含 Dart 源码与依赖声明，平台工程（macos/、android/）在你机器上生成：

```bash
cd spike/phase0
flutter create --platforms=macos,android --project-name ai_reader_spike .
flutter pub get
```

### ⚠️ macOS 必做：放开网络与文件权限（否则连不上 Ollama / 打不开文件）

Flutter 生成的 macOS 工程默认沙盒**不允许发起网络请求**。编辑以下两个文件，在 `<dict>` 里加两条：

`macos/Runner/DebugProfile.entitlements` 和 `macos/Runner/Release.entitlements`：

```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
```

然后运行：

```bash
flutter run -d macos
```

## 二、Android 端运行

### ⚠️ Android 必做：允许 HTTP 明文访问局域网（Ollama 是 http 不是 https）

编辑 `android/app/src/main/AndroidManifest.xml`，给 `<application` 标签加属性：

```xml
android:usesCleartextTraffic="true"
```

手机连 Mac 同一 Wi-Fi，数据线连接后：

```bash
flutter run -d <设备ID>    # 设备 ID 用 flutter devices 查看
```

App 内把 Ollama 地址改成 `http://<Mac的局域网IP>:11434`（IP 用 `ipconfig getifaddr en0` 查）。

## 三、验收清单（跑完填这张表）

| # | 验证项 | 通过标准 | 结果 | 备注（延迟/问题） |
|---|---|---|---|---|
| 1 | 双端骨架 | 同一工程 macOS 窗口与安卓真机都能启动 | ☐ | |
| 2 | EPUB 解析渲染 | 3 本不同来源公版 EPUB 能打开：目录正确、中文不乱码、段落正常 | ☐ | |
| 3 | 本机 Ollama 链路 | macOS 划选→AI 解释流式返回，首字 < 3s（面板右上角有计时） | ☐ | |
| 4 | 局域网 Ollama 链路 | Android 同样操作成功，记录首字延迟 | ☐ | |

测试用公版书（合法免费下载 EPUB）：

- 中文：维基文库 / Project Gutenberg 中文书（如鲁迅《呐喊》，PG 编号 **27166**）
- 英文：Standard Ebooks（standardebooks.org）任选，排版质量高，适合测排版

> 沙箱实测发现：PG 的老中文 EPUB 目录质量差（《呐喊》只解析出 2 个章节、标题为正文片段）。解析器本身工作正常（Alice 16 章全对），这是源文件的 NCX 目录问题，属于 Phase 1「渲染/目录增强」要处理的真实案例。

## 四、已知取舍（spike 阶段故意为之）

- **自绘纯文本渲染**：不还原图片/CSS 排版。原因：调研发现 `flutter_epub_viewer`（epub.js 方案，功能全）**不支持 macOS**，`epub_view`（全平台）已两年未更新、有依赖冲突风险。spike 用纯 Dart 的 `epubx` 解析 + 自绘，保证双端一定能跑；富文本渲染方案在 Phase 1 立专项评估（候选：epub_view 实测、flutter_inappwebview + epub.js 自封装）。
- **无阅读进度持久化 / 无标注**：Phase 1 内容。
- **翻译按钮已带**（选段 → AI 翻译），顺手验证 G1 链路，非本阶段验收项。

## 五、沙箱预验证结果（2026-07-18，Linux 云环境）

以下项目已在云端沙箱（Flutter 3.35.3 / Dart 3.9）预先验证通过，**不需要你重复**；你只需跑「三、验收清单」里剩下的真机项：

| 已验证 | 方式 | 结果 |
|---|---|---|
| 依赖解析 + 静态分析 | `flutter pub get` + `flutter analyze` | 0 错误 0 警告 |
| 单元/widget 测试 ×9 | `flutter test`（首页、阅读页、Ollama 协议层） | 全部通过 |
| EPUB 真书解析 | Gutenberg《呐喊》(zh) + Alice (en) | 通过；PG 老中文书目录质量差（见上文备注） |
| Ollama 全链路 | 真实模型（Qwen2.5-0.5B, CPU）+ App 的 OllamaClient 跑真实解释提示词 | healthCheck / listModels / chatStream 全通；流式输出正常 |

沙箱 CPU 推理首字延迟约 12.5s（0.5B 模型、无 GPU），仅证明链路正确，**不代表性能**；Apple Silicon + 7B 的真实延迟以你机器实测为准（验收项 3 的 <3s 标准针对你的 Mac）。0.5B 模型的解释质量明显平庸（例子泛化、贴合度弱），与 PRD 中「手机端小模型仅作降级选项」的判断一致。

剩余必须真机验证的项：macOS/Android 构建与运行（验收 1）、真实排版观感（验收 2 的人工部分）、M 系芯片 + 7B/14B 的延迟与解释质量（验收 3）、局域网链路（验收 4）。

## 六、常见问题

- `flutter pub get` 报版本冲突 → `flutter pub upgrade --major-versions` 后重试。
- macOS 上点「AI 解释」转圈后报错 → 九成是忘了加 entitlements（见上文 ⚠️）。
- Android 连不上 → 手机浏览器先开 `http://<Mac-IP>:11434` 看是否显示 `Ollama is running`；不行则回查 `phase0-setup.md` 第 6 节（OLLAMA_HOST 监听设置）。
- 解释质量差 → 换 `qwen2.5:14b` 试；仍差就记录进验收表备注，这本身就是 Phase 0 要收集的数据。
