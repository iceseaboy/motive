<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="Motive">
</p>

<h1 align="center">Motive</h1>

<h3 align="center"><strong>Say it. Walk away.</strong></h3>
<p align="center">A personal AI agent for macOS. Turns intent into completed work, running from your menu bar.</p>

<p align="center">
  <a href="https://github.com/geezerrrr/motive/releases/latest"><img src="https://img.shields.io/github/v/release/geezerrrr/motive?style=flat-square&color=blue" alt="Release"></a>
  <a href="https://github.com/geezerrrr/motive/stargazers"><img src="https://img.shields.io/github/stars/geezerrrr/motive?style=flat-square" alt="Stars"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2015+-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/swift-6.0-orange?style=flat-square" alt="Swift">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License"></a>
</p>

<p align="center">
  <a href="https://motivework.app/docs">Documentation</a> · <a href="https://github.com/geezerrrr/motive/releases/latest">Download</a> · <a href="https://github.com/geezerrrr/motive/issues">Feedback</a>
</p>

---

## Why Motive?

Most AI coding tools require your full attention — you're either watching an editor window or staring at a terminal. Switch away, and you'll miss prompts or return to a stale `[Y/n]` that's been sitting there for minutes.

**Motive lives in your menu bar.** The AI agent works in the background. When it needs you, a native popup drops down — no need to switch apps. One click, done, back to your flow.

| | Desktop Apps | CLI Tools | **Motive** |
|---|---|---|---|
| **Where it lives** | App window | Terminal | Menu bar |
| **When it needs you** | Buried in UI | Waits in terminal | Native popup |
| **Switch away?** | Miss responses | Miss prompts | Finds you |

## Demo

<p align="center">

https://github.com/user-attachments/assets/6209e3d9-60db-4166-a14a-ae90cdbc01d6

</p>

## Features

### Core

- **Intent-first** — Describe tasks in natural language, press Enter, done. No conversation needed.
- **True background execution** — AI works as a background process, like compiling or rendering.
- **Native notifications** — Permission requests and questions appear as macOS-native popups from the menu bar.
- **Ambient status** — Menu bar icon shows progress at a glance without demanding attention.
- **Concurrent sessions** — Run multiple tasks in parallel, each working independently in the background.

### Control & Privacy

- **Trust levels** — Three configurable modes to control what the AI can do autonomously:

  | Level | Behavior |
  |-------|----------|
  | **Careful** | Asks before every edit and shell command |
  | **Balanced** | Auto-approves safe actions, asks for unknown commands |
  | **Yolo** | Full autonomy for trusted environments |

- **Approval system** — Fine-grained file permission policies (create, modify, rename, move, delete, execute) with per-action Always Allow / Ask / Deny.
- **Local-first** — All data stays on your machine. Only AI API requests leave your device.

### Extensibility

- **17 AI providers** — Claude, OpenAI, Gemini, Ollama, OpenRouter, Azure, Bedrock, and more. Bring your own key.
- **50+ built-in skills** — Weather, GitHub, Slack, Notion, Calendar, and others. Enable/disable in Settings.
- **Custom skills** — Create your own skills in `~/.motive/skills/`, no code changes required.
- **Browser automation** — Web scraping, form filling, and multi-step browser workflows.

### Built for Mac

- **Native macOS** — Swift 6, SwiftUI, AppKit. No Electron, no web views.
- **Keychain storage** — API keys stored securely in macOS Keychain.
- **Global hotkey** — `⌥Space` from anywhere, like Spotlight.
- **Multi-language UI** — English, 简体中文, 日本語.

## Quick Start

### Install

Download the latest release:

| Chip | Download |
|------|----------|
| Apple Silicon | [Motive-arm64.dmg](https://github.com/geezerrrr/motive/releases/latest/download/Motive-arm64.dmg) |
| Intel | [Motive-x86_64.dmg](https://github.com/geezerrrr/motive/releases/latest/download/Motive-x86_64.dmg) |

> **First launch:** macOS may block unsigned apps. Go to System Settings → Privacy & Security → Click "Open Anyway".

### Configure

1. Click the menu bar icon → **Settings**
2. Select your AI provider (Claude / OpenAI / Gemini / Ollama)
3. Enter your API key

### Use

1. Press `⌥Space` to open the command bar
2. Describe what you want done
3. Press Enter — the bar disappears, you're free
4. Check the menu bar icon for status; click to view details

For detailed guides, see the [documentation](https://motivework.app/docs).

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌥Space` | Open command bar |
| `↵` | Submit intent |
| `Esc` | Dismiss command bar |
| `⌘,` | Open settings |

## FAQ

<details>
<summary><strong>How is this different from Cursor / Claude Code / Gemini CLI?</strong></summary>

Desktop apps (Cursor, Claude Desktop) require you to stay in their window. CLI tools (Claude Code, Gemini CLI) require you to stay in the terminal — switch away, and you won't notice when they need input.

Motive runs the AI as a background process. When it needs your input, a native popup appears from the menu bar regardless of what app you're in. You respond, it continues.
</details>

<details>
<summary><strong>Why does Motive need Accessibility permission?</strong></summary>

To register the global hotkey (`⌥Space`) that opens the command bar from anywhere. Without it, you'd need to click the menu bar icon every time.
</details>

<details>
<summary><strong>Is my data sent to the cloud?</strong></summary>

Motive is local-first. Sessions and history stay on your machine. The only network traffic is API requests to your chosen AI provider. Use Ollama for fully offline operation.
</details>

<details>
<summary><strong>Can I use a local LLM?</strong></summary>

Yes. Select Ollama as your provider and point it to your local instance.
</details>

<details>
<summary><strong>What can Motive do?</strong></summary>

Anything an AI coding agent can do: refactor code, generate files, run scripts, organize projects, write docs, and more. Under the hood, Motive uses <a href="https://github.com/anomalyco/opencode">OpenCode</a> as its execution engine, which has full filesystem and terminal access.
</details>

## Roadmap

- [ ] **Scheduled tasks** — Set up recurring or time-based tasks that run automatically on a schedule
- [ ] **Memory & RAG** — Long-term memory with retrieval-augmented generation for context-aware assistance
- [ ] **iOS companion** — Send tasks to your Mac from your iPhone
- [ ] **Task templates** — Save and reuse common task patterns with customizable parameters
- [ ] **Multi-agent workflows** — Orchestrate multiple agents working on related tasks

## Build from Source

```bash
git clone https://github.com/geezerrrr/motive.git
cd motive
open Motive.xcodeproj
```

The [OpenCode](https://github.com/anomalyco/opencode) binary is bundled automatically during release builds. For development, place it at `Motive/Resources/opencode`.

## Requirements

- macOS 15.0 (Sequoia) or later
- API key for Claude, OpenAI, Gemini, or local Ollama setup

## Acknowledgments

Powered by [OpenCode](https://github.com/anomalyco/opencode) — the open-source AI coding agent that makes autonomous task execution possible.

---

<p align="center">
  <sub>Let AI wait for you, so you don't have to wait for it.</sub>
</p>
