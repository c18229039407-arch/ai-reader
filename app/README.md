# 林间阅读 App

正式应用工程。当前进度：**Phase 1–3 全部功能代码已完成**（34 项测试全绿），剩真机验证。

## 已实现（对应 PRD 功能编号）

| 模块 | 功能 |
|---|---|
| 导入 A1 | EPUB / TXT 多选导入，内容去重，TXT 自动按「第X章/Chapter N」切章 |
| 公版书 A2/A3 | 内置 Project Gutenberg（Gutendex）搜索 → 一键下载入书架；数据源为可插拔 `BookSource` 接口，随包仅合法源，UI 展示许可说明 |
| 书架 B1/B2 | 封面墙 + 阅读进度条；长按移除；数据全本地（JSON，Syncthing 友好布局） |
| 阅读 C1–C5/C9 | 章节渲染、字号/行距/边距调节、四主题、精确进度恢复、段落高亮、目录抽屉与上下章 |
| AI D1–D4/D7 | 划选 → 右键「AI 解释/翻译」；上下文组装 + 画像个性化；宽屏侧栏/窄屏抽屉 |
| 追问 D5/D6 | 解释面板内「换个例子 / 更深入 / 一句话」+ 自由追问，多轮保留完整上下文 |
| 锚点 D8 | 解释自动留存；段落尾 ✦ 常驻，点击秒开；重开书仍在 |
| 概念本 D10 | 全书留存解释汇总页，可展开回看、跳回原文 |
| 翻译 G1/G2/G3/G4 | 选段即时翻译；全书批量翻译（本地模型零成本、实时落盘、可暂停断点续跑、进度条）；原文/译文/双语对照三种显示模式；UI 明示本地译文为辅助理解级 |
| 同步 E3/E4 数据层 | 状态按设备分文件写入（`state/<书>.<设备>.json`）、读取时自动合并（进度取最新、高亮/解释求并集）——Syncthing 同步目录即可双端互通，无二进制冲突 |
| 设置 F1–F3 | 自动检测 Ollama、模型下拉、AI 总开关、设备标识、首启隐私说明 |

已知简化：高亮为段落级单色；EPUB 图片/CSS 不渲染（渲染专项在 Phase 3）；TXT 仅 UTF-8。

## 在 Mac 上运行

前置：完成 `docs/phase0-setup.md`（Flutter + Ollama + 模型）。

```bash
cd app
flutter create --platforms=macos,android --project-name ai_reader .
flutter pub get
```

macOS 权限（必做，同 spike）：`macos/Runner/DebugProfile.entitlements` 与 `Release.entitlements` 的 `<dict>` 内加入：

```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
```

运行：

```bash
flutter run -d macos
```

## MVP 验收清单（PRD Phase 1 里程碑）

- [ ] 导入一本自己的 EPUB 与一本 TXT，重启 App 后书架仍在
- [ ] 调整字号/主题，重启后设置保留
- [ ] 读到一半退出，再打开回到原位置（章节 + 滚动位置）
- [ ] 划选难懂段落 →「AI 解释」→ 解释确实贴合你在设置里填的画像
- [ ] 解释后的段落出现 ✦，关书重开后 ✦ 仍在，点击秒开留存内容
- [ ] 设置里关闭 AI 后，阅读器右键菜单不再出现 AI 项

## 测试

```bash
flutter test        # 24 项：存储/解析/提示词/合并/翻译/公版源/界面（沙箱已全绿）
flutter analyze     # 0 警告（沙箱已验证）
E2E=1 flutter test test/e2e/phase2_e2e_test.dart  # 真网络+真模型端到端（沙箱已跑通）
```

## 沙箱端到端实录（2026-07-18）

真实 Gutendex 搜索《吶喊》→ 下载 179KB EPUB → 入库 → 真实模型批量翻译前 2 段并落盘续跑，全链路 PASS。注意：沙箱用的 0.5B 小模型译文质量明显不可用（正好验证 G4 的必要性）；真实质量以 Mac 上 qwen2.5:7b/14b 实测为准。

## Android 端运行（Phase 2）

同一套代码。`flutter create` 已含 android 平台后：给 `android/app/src/main/AndroidManifest.xml` 的 `<application` 加 `android:usesCleartextTraffic="true"`（连局域网 Ollama 需要）；App 内 Ollama 地址填 `http://<Mac的IP>:11434`。双端同步：把两台设备的书库目录（macOS 为 `~/Library/Application Support/AIReader`，Android 为应用文档目录）加入同一个 Syncthing 共享文件夹即可。
