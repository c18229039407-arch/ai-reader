# 林间阅读 (Linjian Reader)

[![CI](https://github.com/c18229039407-arch/ai-reader/actions/workflows/ci.yml/badge.svg)](https://github.com/c18229039407-arch/ai-reader/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Android-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.35%2B-02569B?logo=flutter)
![License](https://img.shields.io/badge/license-TBD-lightgrey)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](./CONTRIBUTING.md)

English | **[简体中文](./README.md)**

> A local-first, cross-device, AI-assisted open-source ebook reader.
> Keep your books on your own devices; when a concept blocks you, the AI explains it in plain language with analogies drawn from *your* daily life.

**Status**: feature-complete in code (Phase 1–3, all tests green); on-device verification in progress. No release yet.

## What it is

Most readers solve "rendering text". The real obstacle is usually **comprehension** — an unfamiliar term or a dense argument makes people give up. Linjian Reader's claim: *a reader should help you across the gap the second you get stuck*, and personally — the same concept deserves a different analogy for a programmer than for a chef.

### Highlights

- **AI concept explanation**: select text → plain-language explanation + an example tailored to your profile; follow-ups, alternate examples, depth control; consistent terminology within a book.
- **✦ Explanation anchors**: explained passages keep a persistent marker; tap to reopen the saved explanation instantly (no re-inference). All explanations aggregate into a per-book concept notebook.
- **AI translation**: instant selection translation; whole-book batch translation on a local model (pause/resume, checkpointed) with original / translated / bilingual views.
- **Local-first**: books and all reading data stay on your devices. No account, no cloud, no telemetry.
- **Zero-cost AI by default**: auto-detects local [Ollama](https://ollama.com) (Apple Silicon recommended); bring your own OpenAI-compatible / Anthropic key if you prefer.
- **Two platforms, one codebase**: macOS + Android (Flutter), synced peer-to-peer via [Syncthing](https://syncthing.net) — no server.
- **Full reader**: EPUB/TXT/PDF, typography controls, four themes, precise progress restore, highlights, notes, bookmarks, in-book search, tagged shelf, backup export/import.
- **Built-in public-domain search**: one-tap import from Project Gutenberg and other legal sources; pluggable source adapters.

## What it is NOT

**This project is not a book-finding/downloading tool and does not integrate any piracy sources.** Bundled sources are legal public-domain sites only; importing relies on files you own. The source-adapter layer is pluggable, and this codebase contains — and accepts — no adapters targeting infringing sites (see PRD §8 and [CONTRIBUTING](./CONTRIBUTING.md)).

## Quick start

Prerequisites: macOS (Apple Silicon recommended), [Flutter](https://docs.flutter.dev/get-started/install), [Ollama](https://ollama.com).

```bash
git clone https://github.com/c18229039407-arch/ai-reader.git
cd ai-reader/app
flutter create --platforms=macos,android --project-name ai_reader .
flutter pub get
# macOS: allow network/file access in the two entitlements files (see app/README.md)
flutter run -d macos
```

Local model: `ollama pull qwen2.5:7b`.

## Tests

```bash
cd app
flutter analyze   # 0 issues
flutter test      # 34 unit/widget tests
E2E=1 flutter test test/e2e/phase2_e2e_test.dart   # end-to-end (network + Ollama required)
```

## License

**TBD** (will be settled before the first release; see [docs/license-guide.md](./docs/license-guide.md)). Until a LICENSE file lands, all rights reserved — open an issue if you want to reuse the code.

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](./CONTRIBUTING.md), including the hard line on data sources.
