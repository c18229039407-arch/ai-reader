# AI Reader（暂定名）

> 一个本地优先、双端可用、AI 辅助理解的开源电子书阅读器。
> 把书放进本地书架；读到看不懂的概念时，AI 用通俗语言和贴合你生活经验的例子讲给你听。

**状态**：立项阶段（Phase 0 技术验证中）。尚无可用版本。

---

## 这是什么

大多数阅读器解决的是「把字显示出来」，而真正的阅读障碍常发生在**理解层**——一个陌生术语、一段绕的论证，会让人卡住甚至弃读。AI Reader 的主张是：**阅读器不该只翻页，还该在你卡住的那一秒帮你跨过去**，而且这个「帮」是个性化的——同一个概念，对程序员和对厨师，应该给不同的类比。

核心特性（规划中，详见 [PRD](./PRD.md)）：

- **AI 概念解释**：划选文字 → 通俗解释 + 贴合你职业/生活经验的例子，支持追问和深度切换。
- **AI 翻译辅助**：英文书选段即时中译；整本书可用本地模型夜间挂机批量翻译，零 API 成本。
- **本地优先**：书籍和阅读数据全部存在你自己的设备上，没有云账户，没有服务器。
- **默认零成本 AI**：自动检测本机 [Ollama](https://ollama.com)（Apple Silicon 推荐），也可自带任意 OpenAI 兼容 / Anthropic API Key。
- **双端**：macOS + Android（一套 Flutter 代码，两套交互习惯），经 [Syncthing](https://syncthing.net) 点对点同步进度与标注。
- **公版书内置搜索**：Project Gutenberg、Standard Ebooks、维基文库等合法公版源一键导入。

## 这不是什么

**本项目不是找书/下载工具，不提供也不对接任何盗版内容源。** 随包数据源仅包含合法公版书站点；书籍导入依赖用户自有文件。数据源以可插拔适配器实现，代码库不包含、也不接受任何针对侵权站点的定向适配器（详见 PRD §8 与 [CONTRIBUTING](./CONTRIBUTING.md)）。

## 文档

| 文档 | 内容 |
|---|---|
| [PRD.md](./PRD.md) | 产品需求、功能清单、开发路线图（基准文档） |
| [docs/phase0-setup.md](./docs/phase0-setup.md) | Phase 0 开发环境搭建手册（macOS） |
| [docs/architecture.md](./docs/architecture.md) | 技术架构与核心接口设计 |
| [docs/license-guide.md](./docs/license-guide.md) | 开源许可证选择指南（待定项） |

## 路线图（摘要）

| 阶段 | 目标 |
|---|---|
| Phase 0 | 技术验证：Flutter 双端骨架 / EPUB 渲染 / Ollama 本地与局域网链路 |
| Phase 1 (MVP) | macOS 单端闭环：本地看书 + AI 个性化解释，零 API 费用 |
| Phase 2 (V1) | Android 端 + Syncthing 同步 + 翻译辅助 + 公版书搜索 |
| Phase 3 (V2) | 体验完善 + 可插拔数据源 + 社区生态 |

完整版见 [PRD 第 9 章](./PRD.md)。

## 技术栈

Flutter（macOS + Android）· SQLite / FTS5 · Ollama（默认 AI Provider，抽象接口可替换）· Syncthing（同步，App 外部工具）

## 许可证

待定（发布首个可用版本前确定），候选分析见 [docs/license-guide.md](./docs/license-guide.md)。

## 参与

项目处于极早期，欢迎通过 Issue 讨论。贡献规范见 [CONTRIBUTING.md](./CONTRIBUTING.md)。
