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

- 中文：维基文库 / Project Gutenberg 中文书（如鲁迅《呐喊》，PG 编号 25305）
- 英文：Standard Ebooks（standardebooks.org）任选，排版质量高，适合测排版

## 四、已知取舍（spike 阶段故意为之）

- **自绘纯文本渲染**：不还原图片/CSS 排版。原因：调研发现 `flutter_epub_viewer`（epub.js 方案，功能全）**不支持 macOS**，`epub_view`（全平台）已两年未更新、有依赖冲突风险。spike 用纯 Dart 的 `epubx` 解析 + 自绘，保证双端一定能跑；富文本渲染方案在 Phase 1 立专项评估（候选：epub_view 实测、flutter_inappwebview + epub.js 自封装）。
- **无阅读进度持久化 / 无标注**：Phase 1 内容。
- **翻译按钮已带**（选段 → AI 翻译），顺手验证 G1 链路，非本阶段验收项。

## 五、常见问题

- `flutter pub get` 报版本冲突 → `flutter pub upgrade --major-versions` 后重试。
- macOS 上点「AI 解释」转圈后报错 → 九成是忘了加 entitlements（见上文 ⚠️）。
- Android 连不上 → 手机浏览器先开 `http://<Mac-IP>:11434` 看是否显示 `Ollama is running`；不行则回查 `phase0-setup.md` 第 6 节（OLLAMA_HOST 监听设置）。
- 解释质量差 → 换 `qwen2.5:14b` 试；仍差就记录进验收表备注，这本身就是 Phase 0 要收集的数据。
