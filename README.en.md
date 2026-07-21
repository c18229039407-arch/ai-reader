<p align="center"><img src="app/assets/icon/logo.png" width="108" alt="Linjian Reader"></p>

# 林间阅读 (Linjian Reader)

[![CI](https://github.com/c18229039407-arch/ai-reader/actions/workflows/ci.yml/badge.svg)](https://github.com/c18229039407-arch/ai-reader/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Android-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.35%2B-02569B?logo=flutter)
[![License: GPL v3](https://img.shields.io/badge/license-GPL--3.0-blue)](./LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](./CONTRIBUTING.md)

English | **[简体中文](./README.md)**

> A local-first, cross-device, AI-assisted open-source ebook reader.
> Keep your books on your own devices; when a concept blocks you, the AI explains it in plain language with analogies drawn from *your* daily life.

**Status**: feature-complete in code (all tests green); on-device verification in progress. Alpha builds on [Releases](https://github.com/c18229039407-arch/ai-reader/releases).

## What it is

Most readers solve "rendering text". The real obstacle is usually **comprehension** — an unfamiliar term or a dense argument makes people give up. Linjian Reader's claim: *a reader should help you across the gap the second you get stuck*, and personally — the same concept deserves a different analogy for a programmer than for a chef.

## What it is NOT

**This project is not a book-finding/downloading tool and does not integrate any piracy sources.** Bundled sources are legal public-domain sites only; importing relies on files you own. The source-adapter layer is pluggable, and this codebase contains — and accepts — no adapters targeting infringing sites (see PRD §8 and [CONTRIBUTING](./CONTRIBUTING.md)).

## Quick start

### Option 1 — Download (recommended, zero dev environment)

1. Install the AI engine: get [Ollama](https://ollama.com), then run `ollama pull qwen2.5:7b`
2. Download `linjian-reader-macos.zip` (macOS) or `linjian-reader-android.apk` (Android) from [Releases](https://github.com/c18229039407-arch/ai-reader/releases)
3. macOS first launch: **right-click → Open** (unsigned build); if blocked, run `xattr -cr <App path>`

### Option 2 — Build from source

Prerequisites: [Flutter](https://docs.flutter.dev/get-started/install), [Ollama](https://ollama.com).

```bash
git clone https://github.com/c18229039407-arch/ai-reader.git
cd ai-reader/app
flutter create --platforms=macos,android --project-name ai_reader .
flutter pub get
# macOS: allow network/file access in the two entitlements files (see app/README.md)
flutter run -d macos
```

## Capability map

Organized by a book's journey — from finding it to carrying it with you:

| Journey | Capability | Notes |
|---|---|---|
| **Find** | Public-domain search | Gutenberg + Chinese Wikisource in parallel; per-source direct/proxy probing |
| | Chinese-first, 3-layer retrieval | Chinese search (auto Simplified↔Traditional) ∥ 60+ classics title atlas ∥ AI title translation — searching 「瓦尔登湖」 lands on the public-domain *Walden* |
| | Copyright answers | Searching an in-copyright title (e.g. *Sapiens*) explains why it can't be free, with legit purchase links |
| | Find elsewhere | One-tap web/Douban/WeRead/Kongfz links; import the file you obtain |
| **Read** | Formats | EPUB / TXT / PDF; light rich text (heading levels / bold / italics / inline images) |
| | Two reading modes | Vertical scroll / horizontal paging (custom pagination engine + cover-flip animation) |
| | Immersive mode | Tap the text to hide all chrome; Esc or tap again to restore |
| | Typography | Font size/line height/letter & paragraph spacing/first-line indent/margins/9 paper themes/bundled LXGW WenKai |
| | Desktop shortcuts | Arrows/Space to page, ⌘F in-book search, ⌘B bookmark |
| **Understand** (core) | AI concept explanation | Select → plain-language explanation with analogies from *your* occupation & hobbies; follow-ups, alternate examples, depth control |
| | ✦ Explanation anchors | Explained passages keep a marker; reopen instantly, no re-inference; aggregates into a concept notebook |
| | AI translation | Instant selection translation + whole-book overnight batch (checkpointed); original/translated/bilingual |
| | AI companion | "Ask this book" — multi-turn chat grounded in the current chapter and your profile |
| **Listen** | TTS | Dual engine: system voices (free) / Doubao speech LLM (BYO key, licensed voices only); per-paragraph highlight, auto chapter advance, sleep timer |
| **Keep** | Annotations | Sentence-level highlights, notes, bookmarks, in-book search, tagged shelf |
| | Reading stats | Day/week/month/year time, streaks, per-book ranking, half-year heatmap (multi-device merge) |
| | Quote cards | Turn any selection into a shareable card image (3 themes) |
| **Carry** | Local-first | All data stays on device; Syncthing P2P sync; one-tap backup export/import |

## Tech stack (in plain words)

| Tool | What it is | Why we chose it |
|---|---|---|
| **Flutter + Dart** | Cross-platform UI framework: one codebase compiles to a native macOS app and an Android APK | The project's iron rules are "no server, two platforms, maintainable by one person". Flutter is the only option that gives desktop + mobile from one codebase with self-drawn rendering and a big-enough ecosystem. Without it: write everything twice in Swift and Kotlin |
| **epubx** | EPUB parser: splits .epub into chapters, text, images, metadata | The most mature EPUB parser in Dart. We built a light rich-text layer on top (headings/quotes/bold/italics/images + noise cleanup) while keeping the plain-text layer untouched — so highlight and AI-selection anchoring reuse it for free |
| **pdfrx** | PDF renderer | Built on pdfium (the engine inside Chrome); reliable CJK rendering. Pinned to 1.x for our Dart version |
| **Local JSON storage (no database)** | Each book's progress/highlights/notes = one JSON file, written per device | Deliberately not SQLite: JSON files sync cleanly over Syncthing with no binary conflicts — the entire "serverless multi-device sync" capability rests on this choice. Reads merge across devices: latest progress wins, annotations are unioned |
| **LlmClient abstraction (ours)** | One interface, any AI behind it: local Ollama, LM Studio, DeepSeek or any OpenAI-compatible service | Zero-cost by default (auto-detects local models); bring your own key for more power. No vendor lock-in — switching providers is a URL change |
| **Custom pagination engine** | Measures real text layout to cut chapters into exact pages (long paragraphs split at line boundaries) | Flutter has no ready-made CJK pagination. Measurement and rendering share one set of style constants, so font/size changes repaginate correctly; slices provably reassemble into the full text (locked by tests) |
| **flutter_tts + Doubao speech** | Dual TTS: system voices (free, offline) + Doubao speech LLM (cloud, high quality, licensed voice library only) | A free floor and a premium option. Hard line: no cloning of any real person's voice (voice rights under PRC Civil Code art. 1023) |
| **LXGW WenKai Lite** | Bundled open-source CJK font (SIL OFL 1.1) | System serif fonts vary wildly across platforms (worst on Android). WenKai is the most book-like open CJK font; 9.5 MB buys a consistent reading feel everywhere |
| **GitHub Actions CI** | Every tag builds the .app and .apk on cloud runners and attaches them to Releases | Zero servers; maintainers don't even need a Mac to ship. The "download and run" zero-environment install depends entirely on this |
| **Syncthing (external)** | Peer-to-peer file sync, device to device, no server in between | We refuse to run a sync backend (cost, ops, data liability). The data format is designed for it; the app works fully standalone without it |

> Selection principle: **having no server *is* the architecture** — every choice must work under "zero operating cost, user data never leaves the device, maintainable by one person".

## Tests

```bash
cd app
flutter analyze   # 0 issues
flutter test      # 109 unit/widget tests
E2E=1 flutter test test/e2e/phase2_e2e_test.dart   # end-to-end (network + Ollama required)
```

## License

[GPL-3.0](./LICENSE). Anyone distributing derivatives must open-source their modifications — a structural deterrent against piracy-bundled forks (rationale in [docs/license-guide.md](./docs/license-guide.md)). The bundled font "LXGW WenKai Lite" is licensed under [SIL OFL 1.1](./app/assets/fonts/OFL.txt) (© LXGW).

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](./CONTRIBUTING.md), including the hard line on data sources.
