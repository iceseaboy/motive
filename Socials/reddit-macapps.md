标题：
Motive — a native Swift menu bar app that runs AI agents in the background

正文：

Hey r/macapps, solo dev here. I built a menu bar AI assistant in Swift 6 / SwiftUI — no Electron, no web views, fully native.

I've been using AI coding tools for a while, but they all run in a terminal or editor window that demands your attention. I wanted something that fits the Mac way — lightweight, lives in the menu bar, stays
 out of your way.

How it works: ⌥Space to open, describe what you want, dismiss. Go back to whatever you were doing. The AI agent runs in the background. When it needs your input — a permission to run a shell command, a clarifying question — it pops up a native macOS dialog. You respond, it continues. Menu bar icon shows you the current status at a glance.

Built with:
- Swift 6 / SwiftUI / AppKit
- Keychain for API key storage
- SwiftData for local persistence
- Supports Claude, OpenAI, Gemini, Ollama, and others — bring your own key

Free and open source: https://github.com/geezerrrr/motive

[screenshot / GIF]

What's your preferred way to interact with AI tools on Mac — terminal, editor plugin, or standalone app?
