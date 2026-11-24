# AI Status Widget for macOS

![Platform](https://img.shields.io/badge/Platform-macOS%2014%2B%20(Apple%20Silicon)-blue)
![UI](https://img.shields.io/badge/UI-Liquid%20Glass-38c7ff)
![License](https://img.shields.io/badge/License-MIT-green)

**English** | [简体中文](README.zh-CN.md)

**TL;DR:** Neither **Google Antigravity** nor **WorkBuddy** provides an always-visible macOS desktop widget for checking remaining model quotas, reset countdowns, and daily token/credit consumption. **AI Status Widget** solves this with a native `344×116` **macOS Liquid Glass** desktop widget (`NSPanel` at wallpaper level) paired with a browser-based **Industrial Web Setup Workbench**, reading **100% locally** with zero cloud polling and zero account-ban risk.

---

## Comparison: Official Apps vs. AI Status Widget

| Feature | Antigravity / WorkBuddy Official UI | AI Status Widget |
| :--- | :--- | :--- |
| **Desktop Residency** | Must open app window or browser tab | Always-on desktop layer (`level = -2147483602`), never blocks windows |
| **Reset Countdown** | Buried inside model settings menu | Live second-by-second countdown pill (`3h40m`) |
| **Daily Token Telemetry** | Not aggregated per day in one view | Unified `↑ Input` / `↓ Output` token counters for both tools |
| **WorkBuddy Credit Tracking** | Cloud-only balance | Local SQLite (`workbuddy.db`) + daily check-in logs (`main.log`) auto-ledger |
| **Account Safety** | — | Zero external API requests; 100% local read-only telemetry |
| **Visual Design** | Standard app windows | Adaptive Light/Dark **Liquid Glass** (`NSGlassEffectView` / `NSVisualEffectView`) + 1px specular rim |

---

## Supported Tools & Models

- **Google Antigravity** (via local `hub_*.json` daemon RPC + `brain/*/transcript.jsonl`):
  - **Gemini Models**: `Gemini 4 Neon`, `Gemini 4 Carbon`, `Gemini 4 Argon`, `Gemini 4 Hydrogen`, `Gemini 3.8 Flash`, `Orchestrator` (5-hour quota % & reset countdown)
  - **Claude & GPT Models**: `Claude Opus 5.5`, `Claude Sonnet 5.5`, `GPT-OSS 120B` (quota % tracking)
  - **Daily Tokens**: Today's estimated `Input` and `Output` tokens
- **WorkBuddy** (via read-only `~/.workbuddy/workbuddy.db` & `~/.workbuddy/logs/main.log`):
  - **Credit Balance & Daily Usage**: Calibrated balance with automatic addition of daily check-ins (`claimDailyCheckin`) and automatic deduction of per-turn usage (`session_usage.credit_json`)
  - **Daily Tokens & Sessions**: Today's `Input` / `Output` tokens and active session count

---

## Installation

### Option 1: Download Pre-built Release (Apple Silicon `arm64`)

1. Download `AIStatusWidget-arm64.zip` from [GitHub Releases](../../releases).
2. Unzip and move `AIStatusWidget.app` to `/Applications/`.
3. Remove the macOS quarantine attribute on first launch:

```bash
xattr -cr "/Applications/AIStatusWidget.app"
```

4. Double-click `AIStatusWidget.app` in `/Applications`.

### Option 2: Build from Source

Requires macOS with Swift (`swiftc` / Xcode Command Line Tools) and `/usr/bin/python3`.

```bash
git clone https://github.com/ARRIIIIIS/ai-status-widget.git
cd ai-status-widget
./build.sh
open ./AIStatusWidget.app
```

---

## Usage & Controls

- **Anti-Mistouch Drag**: Press and hold any non-button area on the widget for **0.25s** to drag and reposition. Position is saved automatically and clamped to screen bounds on relaunch.
- **Refresh Button**: Click the circular glass `↻` button at top-center for instant refresh with caustics glow feedback.
- **Menu Bar Icon**: Single bolt icon in the macOS menu bar with 3 items: `Settings Wizard...`, `Restart`, and `Quit`.
- **Web Setup Workbench**: Opens in your default browser (`http://127.0.0.1:<port>/`) with `EN | 中文` switching, live 4-cell HUD telemetry, separate Antigravity & WorkBuddy calibration tabs, refresh interval (`15s / 30s / 60s`), and Launch at Login.

---

## FAQ

### Will this get my WorkBuddy or Antigravity account banned?
No. **AI Status Widget** makes zero external network requests. WorkBuddy data is read locally in read-only mode from `~/.workbuddy/workbuddy.db` and `~/.workbuddy/logs/main.log`. Antigravity data is queried from your local `127.0.0.1` desktop daemon.

### How does WorkBuddy credit tracking work without a cloud API?
WorkBuddy persists every turn's credit cost in `workbuddy.db` (keyed by UUIDv7 / `req-` millisecond timestamps) and logs every daily check-in reward in `main.log`. Enter your current balance once in the Web Setup Workbench, and the widget automatically adds daily check-ins and deducts per-turn usage.

### How do I fix "AIStatusWidget.app cannot be opened because it is from an unidentified developer"?
Run `xattr -cr "/Applications/AIStatusWidget.app"` in Terminal, or right-click the app and select **Open**.
