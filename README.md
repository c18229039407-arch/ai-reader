<p align="center"><img src="app/assets/icon/logo.png" width="108" alt="林间阅读"></p>

# 林间阅读

[![CI](https://github.com/c18229039407-arch/ai-reader/actions/workflows/ci.yml/badge.svg)](https://github.com/c18229039407-arch/ai-reader/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Android-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.35%2B-02569B?logo=flutter)
[![License: GPL v3](https://img.shields.io/badge/license-GPL--3.0-blue)](./LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](./CONTRIBUTING.md)

**[English](./README.en.md)** | 简体中文

> 一个本地优先、双端可用、AI 辅助理解的开源电子书阅读器。
> 把书放进本地书架；读到看不懂的概念时，AI 用通俗语言和贴合你生活经验的例子讲给你听。

**状态**：功能开发完成（Phase 1–3 代码全绿），真机验证阶段。尚无正式发行版。

<!-- TODO: 真机运行后补两张截图（macOS 阅读页 + AI 解释侧栏；Android 底部抽屉） -->

---

## 这是什么

大多数阅读器解决的是「把字显示出来」，而真正的阅读障碍常发生在**理解层**——一个陌生术语、一段绕的论证，会让人卡住甚至弃读。林间阅读的主张是：**阅读器不该只翻页，还该在你卡住的那一秒帮你跨过去**，而且这个「帮」是个性化的——同一个概念，对程序员和对厨师，应该给不同的类比。

### 核心特性

- **AI 概念解释**：划选文字 → 通俗解释 + 贴合你职业/生活经验的例子；支持追问、换例、深度切换；同书同术语解释保持口径一致。
- **✦ 解释锚点**：解释过的段落常驻小标记，点击秒开留存内容（不重复请求模型）；全书解释自动沉淀为「概念本」。
- **AI 翻译辅助**：选段即时中译；整本书可用本地模型夜间挂机批量翻译（可暂停/断点续跑），支持原文/译文/双语对照。
- **本地优先**：书籍与全部阅读数据只存本机；无账号、无云端、无上报。
- **默认零成本 AI**：自动检测本机 [Ollama](https://ollama.com)（Apple Silicon 推荐），也可自带 OpenAI 兼容 / Anthropic API Key。
- **双端**：macOS + Android 一套 Flutter 代码；经 [Syncthing](https://syncthing.net) 点对点同步进度与标注，无需服务器。
- **完整阅读器**：EPUB/TXT/PDF、轻量富文本（标题分级/粗斜体/插图）、滚动与左右翻页双模式（覆盖式翻页动画）、沉浸模式（点正文隐藏工具栏）、桌面快捷键（方向键/空格翻页、⌘F 搜索、⌘B 书签）、内置霞鹜文楷字体（OFL）、排版精调（字号/行距/字距/段距/首行缩进/页边距）、九种纸色、进度记忆、高亮、笔记、书签、书内检索、标签书架、备份导出。
- **朗读（TTS）**：双引擎——系统语音（免费默认）或豆包语音大模型（自备 Key，官方授权音色）；逐段朗读、当前段高亮跟随、自动续章；多音色、语速/音调调节、15/30/60 分钟与「读完本章」定时关闭。
- **阅读统计**：日/周/月/年时长、连续阅读天数、单书排行，GitHub 式半年热力图直观呈现阅读习惯（多设备合并）。
- **书摘分享卡片**：划选文字一键生成三款精美卡片图片（暖纸/夜墨/松绿），保存即分享。
- **AI 助读**：「问这本书」——带书名/章节/画像上下文的整书多轮对话，流式作答。
- **公版书内置搜索**：Project Gutenberg + 中文维基文库（含鲁迅、朱自清、老舍等已过版权期的近现代中文作品）一键导入；中文优先检索三层策略——中文直搜（简繁回退）∥ 60+ 名著词典 ∥ AI 书名翻译（用你配置的模型），搜「瓦尔登湖」自动找到公版原著 Walden；数据源可插拔。

## 这不是什么

**本项目不是找书/下载工具，不提供也不对接任何盗版内容源。** 随包数据源仅包含合法公版书站点；书籍导入依赖用户自有文件。数据源以可插拔适配器实现，代码库不包含、也不接受任何针对侵权站点的定向适配器（详见 [PRD §8](./PRD.md) 与 [CONTRIBUTING](./CONTRIBUTING.md)）。

## 快速开始

### 方式一：直接下载（推荐，无需任何开发环境）

1. 装 AI 引擎：到 [ollama.com](https://ollama.com) 下载安装 Ollama（Mac 拖进应用程序即可），然后终端执行一行：`ollama pull qwen2.5:7b`
2. 到 [Releases](https://github.com/c18229039407-arch/ai-reader/releases) 下载 `linjian-reader-macos.zip`（macOS）或 `linjian-reader-android.apk`（Android），解压/安装即用
3. macOS 首次打开：**右键 → 打开**（未签名构建）；若提示已损坏，终端执行 `xattr -cr <App路径>`

### 方式二：从源码构建（开发者）

前置：[Flutter](https://docs.flutter.dev/get-started/install) + Ollama。零基础环境搭建看 [docs/phase0-setup.md](./docs/phase0-setup.md)。

```bash
git clone https://github.com/c18229039407-arch/ai-reader.git
cd ai-reader/app
flutter create --platforms=macos,android --project-name ai_reader .
flutter pub get
# macOS 需放开沙盒网络/文件权限（两处 entitlements，详见 app/README.md）
flutter run -d macos
```

## 仓库结构

```
├── PRD.md              产品需求文档（功能清单 + 路线图，基准文档）
├── app/                Flutter 应用（Phase 1–3 已实现，见 app/README.md）
├── spike/phase0/       Phase 0 技术验证工程（存档参照）
├── docs/
│   ├── phase0-setup.md 开发环境搭建手册（macOS，零基础可跟）
│   ├── architecture.md 技术架构与核心接口
│   └── license-guide.md 许可证选择指南（待定项）
└── .github/workflows/  CI（flutter analyze + 全量测试）+ 双端构建发布
```

## 路线图与进度

| 阶段 | 内容 | 状态 |
|---|---|---|
| Phase 0 | 技术验证：双端骨架 / EPUB 解析 / Ollama 链路 | ✅ 完成（含沙箱实测） |
| Phase 1 | macOS 闭环：书架 + 阅读器 + AI 解释 + 锚点 | ✅ 代码完成 |
| Phase 2 | Android + Syncthing 同步 + 批量翻译 + 公版书搜索 | ✅ 代码完成 |
| Phase 3 | 笔记书签 / 检索 / PDF / 书架增强 / 备份 | ✅ 代码完成 |
| 验证 | 真机构建、7B 模型质量实测、双端同步实测 | 🚧 进行中 |
| 后续 | 完整 HTML 排版还原、多语言 UI、iOS/Windows/Linux | 🤝 欢迎贡献 |

完整版见 [PRD 第 9 章](./PRD.md)。

## 测试

```bash
cd app
flutter analyze   # 0 警告
flutter test      # 109 项单元/界面测试
E2E=1 flutter test test/e2e/phase2_e2e_test.dart   # 端到端（需网络 + Ollama）
```

## 能力地图

按一本书的旅程组织——从找到它，到读完带走它：

| 旅程 | 能力 | 说明 |
|---|---|---|
| **找书** | 公版书搜索 | Gutenberg + 中文维基文库双源并行，各自独立探测直连/代理 |
| | 中文优先三层检索 | 中文直搜（简繁自动回退）∥ 60+ 名著词典 ∥ AI 书名翻译，搜「瓦尔登湖」直达公版原著 Walden |
| | 版权答疑 | 搜到版权期内名著（如《人类简史》）时说清「为什么搜不到 + 去哪买正版」 |
| | 站外找书 | 网页搜索/豆瓣/微信读书/孔网一键直达，下载后「导入书籍」进书架 |
| **读** | 多格式 | EPUB / TXT / PDF；轻量富文本（标题分级/粗斜体/插图） |
| | 双阅读模式 | 上下滚动 / 左右翻页（自研分页引擎 + 覆盖式翻页动画） |
| | 沉浸模式 | 点正文隐藏全部工具栏；Esc 或再点恢复 |
| | 排版精调 | 字号/行距/字距/段距/首行缩进/页边距/九种纸色/霞鹜文楷 |
| | 桌面快捷键 | 方向键/空格翻页，⌘F 书内搜索，⌘B 书签 |
| **懂**（核心） | AI 概念解释 | 划选即解释，例子贴合你的职业与爱好；追问/换例/深浅切换 |
| | ✦ 解释锚点 | 解释过的段落常驻标记，秒开不重复请求；沉淀为「概念本」 |
| | AI 翻译 | 选段即译 + 整本书夜间挂机批量翻译（断点续跑），原文/译文/双语 |
| | AI 助读 | 「问这本书」整书多轮对话，带章节语境与个人画像 |
| **听** | TTS 朗读 | 系统语音（免费）/ 豆包语音大模型（自备 Key）双引擎；逐段高亮跟随、自动续章、定时关闭 |
| **记** | 标注体系 | 句级高亮、笔记、书签、书内检索、标签书架 |
| | 阅读统计 | 日/周/月/年时长、连续天数、单书排行、半年热力图（多设备合并） |
| | 书摘卡片 | 划选生成三款分享卡片图片 |
| **带走** | 本地优先 | 全部数据只在本机；Syncthing 点对点同步；一键备份导出/导入 |

## 技术栈（每一项都说人话）

| 工具 | 是什么 | 为什么选它 |
|---|---|---|
| **Flutter + Dart** | 跨平台 UI 框架：一套代码同时编译成 macOS 原生应用和 Android APK | 项目铁律是「无服务器、双端、一个人可维护」。Flutter 是唯一同时满足「桌面+移动一份代码、渲染自绘不看系统脸色、生态足够大」的选择。不用它就要各写一遍 Swift 和 Kotlin，工作量×2 |
| **epubx** | EPUB 解析库：把 .epub 文件拆成章节、正文、插图、元数据 | Dart 生态里最成熟的 EPUB 解析器。我们在它之上自研了轻量富文本层（标题/引用/粗斜体/插图 + 噪音清洗），纯文本层不动——高亮和 AI 划选的定位机制因此零成本复用 |
| **pdfrx** | PDF 渲染库 | 基于 pdfium（Chrome 同款内核），中文渲染可靠。锁 1.x 版本因为 2.x 要更新的 Dart |
| **本地 JSON 存储（无数据库）** | 每本书的进度/高亮/笔记 = 一个 JSON 文件，按设备分文件写 | 刻意不用 SQLite：JSON 文件可以被 Syncthing 直接同步且不产生二进制冲突——「多设备无服务器同步」整个能力就建立在这个选型上。读取时跨设备合并：进度取最新，标注求并集 |
| **LlmClient 抽象层（自研）** | 一个接口背后可插拔任何 AI：本机 Ollama、LM Studio、DeepSeek 等一切 OpenAI 兼容服务 | 默认零成本（自动扫描本机模型），想要更强就自备 Key。不锁死任何厂商——今天 DeepSeek 明天换别家，改个地址就行 |
| **自研分页引擎** | 用文字实测排版把章节精确切成页（长段落按行边界跨页断开） | Flutter 没有现成的中文分页方案。测量与渲染共用同一套样式常量，改字号/字体分页自动跟随；切片可无损拼回全文（有测试锁定） |
| **flutter_tts + 豆包语音** | 朗读双引擎：系统 TTS（免费离线）+ 豆包语音大模型（云端高音质，仅官方授权音色） | 免费的保底、好听的可选；红线：不接任何真人声音克隆（民法典 1023 条声音权益） |
| **霞鹜文楷 Lite** | 内置开源中文字体（SIL OFL 1.1） | 系统宋体各平台观感不一，安卓尤其差。文楷是中文阅读圈公认最有书卷气的开源字体，随包 9.5MB 换全平台统一书感 |
| **GitHub Actions CI** | 每次打 tag 自动在云端 macOS/Linux 机器上构建 .app 和 .apk 挂到 Releases | 项目零服务器、维护者无需 Mac 开发环境也能发版；用户「下载即用」的零环境安装完全靠它 |
| **Syncthing（外部工具）** | 点对点文件同步，设备间直连不经过任何服务器 | 不自建同步后端（要钱要运维要担数据责任）。数据格式为它设计好，用户装不装都不影响单机使用 |

> 选型总原则：**没有服务器就是架构**——每一项都必须在「零运营成本、用户数据不出设备、一个人维护得动」的约束下工作。

## 许可证

[GPL-3.0](./LICENSE)。任何分发本项目衍生品的行为必须同样开源其修改。内置字体「霞鹜文楷 Lite」以 [SIL OFL 1.1](./app/assets/fonts/OFL.txt) 授权（© LXGW）——这也是对「拿本项目改造成盗版分发版」的制度性威慑（选型分析见 [docs/license-guide.md](./docs/license-guide.md)）。

## 参与

欢迎通过 Issue 讨论与 PR 贡献，规范（含数据源红线）见 [CONTRIBUTING.md](./CONTRIBUTING.md)。
