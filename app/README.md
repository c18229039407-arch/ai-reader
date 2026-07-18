# AI Reader App（Phase 1 MVP）

正式应用工程（spike 验证后的实现版）。MVP 目标：**macOS 单端可用闭环**——本地导入书籍、双主题阅读、进度/高亮持久化、AI 个性化解释 + ✦ 解释锚点，全程零 API 费用（本机 Ollama）。

## 已实现（对应 PRD 功能编号）

| 模块 | 功能 |
|---|---|
| 导入 A1 | EPUB / TXT 多选导入，内容去重，TXT 自动按「第X章/Chapter N」切章 |
| 书架 B1/B2 | 封面墙 + 阅读进度条；长按移除；数据全本地（JSON，Syncthing 友好布局） |
| 阅读 C1–C5/C9 | 章节渲染、字号/行距/边距调节、跟随系统/日间/夜间/纸质主题、精确进度恢复、段落高亮、目录抽屉与上下章 |
| AI D1–D4/D7 | 划选 → 右键「AI 解释/翻译」；解释携带书名/章节/前后文上下文；画像（职业/兴趣/自由描述）个性化类比，可关闭 |
| 锚点 D8 | 解释自动留存；被解释段落尾部常驻 ✦，点击秒开（不重新请求模型）；重开书仍在 |
| 设置 F1–F3 | 自动检测 Ollama、模型下拉、AI 总开关、首启隐私说明 |

MVP 已知简化：高亮为段落级、单色（V1 做字符级多色）；EPUB 图片/CSS 不渲染（V1 渲染专项）；TXT 仅支持 UTF-8（GBK 文件请先转码）。

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
flutter test        # 18 项：存储/解析/提示词/界面（沙箱已全绿）
flutter analyze     # 0 警告（沙箱已验证）
dart run tool/ollama_link_check.dart   # 可选：Ollama 链路端到端检查
```
