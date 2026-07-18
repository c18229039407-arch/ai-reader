# AI Reader（暂定名）

[![CI](https://github.com/c18229039407-arch/ai-reader/actions/workflows/ci.yml/badge.svg)](https://github.com/c18229039407-arch/ai-reader/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Android-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.35%2B-02569B?logo=flutter)
![License](https://img.shields.io/badge/license-TBD-lightgrey)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](./CONTRIBUTING.md)

**[English](./README.en.md)** | 简体中文

> 一个本地优先、双端可用、AI 辅助理解的开源电子书阅读器。
> 把书放进本地书架；读到看不懂的概念时，AI 用通俗语言和贴合你生活经验的例子讲给你听。

**状态**：功能开发完成（Phase 1–3 代码全绿），真机验证阶段。尚无正式发行版。

<!-- TODO: 真机运行后补两张截图（macOS 阅读页 + AI 解释侧栏；Android 底部抽屉） -->

---

## 这是什么

大多数阅读器解决的是「把字显示出来」，而真正的阅读障碍常发生在**理解层**——一个陌生术语、一段绕的论证，会让人卡住甚至弃读。AI Reader 的主张是：**阅读器不该只翻页，还该在你卡住的那一秒帮你跨过去**，而且这个「帮」是个性化的——同一个概念，对程序员和对厨师，应该给不同的类比。

### 核心特性

- **AI 概念解释**：划选文字 → 通俗解释 + 贴合你职业/生活经验的例子；支持追问、换例、深度切换；同书同术语解释保持口径一致。
- **✦ 解释锚点**：解释过的段落常驻小标记，点击秒开留存内容（不重复请求模型）；全书解释自动沉淀为「概念本」。
- **AI 翻译辅助**：选段即时中译；整本书可用本地模型夜间挂机批量翻译（可暂停/断点续跑），支持原文/译文/双语对照。
- **本地优先**：书籍与全部阅读数据只存本机；无账号、无云端、无上报。
- **默认零成本 AI**：自动检测本机 [Ollama](https://ollama.com)（Apple Silicon 推荐），也可自带 OpenAI 兼容 / Anthropic API Key。
- **双端**：macOS + Android 一套 Flutter 代码；经 [Syncthing](https://syncthing.net) 点对点同步进度与标注，无需服务器。
- **完整阅读器**：EPUB/TXT/PDF、排版调节、四主题、进度记忆、高亮、笔记、书签、书内检索、标签书架、备份导出。
- **公版书内置搜索**：Project Gutenberg 等合法公版源一键导入；数据源可插拔。

## 这不是什么

**本项目不是找书/下载工具，不提供也不对接任何盗版内容源。** 随包数据源仅包含合法公版书站点；书籍导入依赖用户自有文件。数据源以可插拔适配器实现，代码库不包含、也不接受任何针对侵权站点的定向适配器（详见 [PRD §8](./PRD.md) 与 [CONTRIBUTING](./CONTRIBUTING.md)）。

## 快速开始

前置：macOS（Apple Silicon 推荐）+ [Flutter](https://docs.flutter.dev/get-started/install) + [Ollama](https://ollama.com)。零基础环境搭建看 [docs/phase0-setup.md](./docs/phase0-setup.md)。

```bash
git clone https://github.com/c18229039407-arch/ai-reader.git
cd ai-reader/app
flutter create --platforms=macos,android --project-name ai_reader .
flutter pub get
# macOS 需放开沙盒网络/文件权限（两处 entitlements，详见 app/README.md）
flutter run -d macos
```

模型准备（本地零成本）：`ollama pull qwen2.5:7b`。

## 仓库结构

```
├── PRD.md              产品需求文档（功能清单 + 路线图，基准文档）
├── app/                Flutter 应用（Phase 1–3 已实现，见 app/README.md）
├── spike/phase0/       Phase 0 技术验证工程（存档参照）
├── docs/
│   ├── phase0-setup.md 开发环境搭建手册（macOS，零基础可跟）
│   ├── architecture.md 技术架构与核心接口
│   └── license-guide.md 许可证选择指南（待定项）
└── .github/workflows/  CI（flutter analyze + 34 项测试）
```

## 路线图与进度

| 阶段 | 内容 | 状态 |
|---|---|---|
| Phase 0 | 技术验证：双端骨架 / EPUB 解析 / Ollama 链路 | ✅ 完成（含沙箱实测） |
| Phase 1 | macOS 闭环：书架 + 阅读器 + AI 解释 + 锚点 | ✅ 代码完成 |
| Phase 2 | Android + Syncthing 同步 + 批量翻译 + 公版书搜索 | ✅ 代码完成 |
| Phase 3 | 笔记书签 / 检索 / PDF / 书架增强 / 备份 | ✅ 代码完成 |
| 验证 | 真机构建、7B 模型质量实测、双端同步实测 | 🚧 进行中 |
| 后续 | 富文本 EPUB 渲染、字符级高亮、多语言 UI、iOS/Windows/Linux | 🤝 欢迎贡献 |

完整版见 [PRD 第 9 章](./PRD.md)。

## 测试

```bash
cd app
flutter analyze   # 0 警告
flutter test      # 34 项单元/界面测试
E2E=1 flutter test test/e2e/phase2_e2e_test.dart   # 端到端（需网络 + Ollama）
```

## 技术栈

Flutter（macOS + Android）· epubx · pdfrx · SQLite-free 本地 JSON 存储（Syncthing 友好）· Ollama（默认 AI Provider，接口可插拔）

## 许可证

**待定**（正式发行前确定），候选分析见 [docs/license-guide.md](./docs/license-guide.md)。在 LICENSE 文件落地前，本仓库默认保留所有权利；如需复用请先开 Issue 联系。

## 参与

欢迎通过 Issue 讨论与 PR 贡献，规范（含数据源红线）见 [CONTRIBUTING.md](./CONTRIBUTING.md)。
