标题：
I stopped watching Claude Code run in my terminal — built a Mac app that lets it work in the background instead

正文：

I was using Claude Code for a refactor task. 40+ files, took about 15 minutes. I sat there the entire time watching edits fly by at a speed I couldn't possibly review. At some point I realized —
I'm not supervising anything, I'm just waiting.

So I built Motive, a macOS menu bar app. The workflow is:

1. ⌥Space → describe the task → dismiss
2. Go do other things
3. Agent needs permission or has a question → native popup appears on your screen
4. You respond → it continues
5. Done → notification

The longer AI tasks get, the more this matters. A 15-minute task where the agent only needs you twice — those two moments are critical. If it's stuck in a background terminal tab, you might not notice for 10 minutes that it's been waiting for your confirmation.

Under the hood it has the full coding agent toolkit — file editing, shell commands, web search, etc. Bring your own API key, works with Claude, OpenAI, Gemini, Ollama, and more.

Free, open source, macOS only: https://github.com/geezerrrr/motive

[screenshot / GIF]

For those of you running long Claude Code sessions — how do you deal with it when it's waiting for input and you've switched to another window?
