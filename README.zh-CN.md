# AI Status Widget for macOS

![Platform](https://img.shields.io/badge/Platform-macOS%2014%2B%20(Apple%20Silicon)-blue)
![UI](https://img.shields.io/badge/UI-Liquid%20Glass-38c7ff)
![License](https://img.shields.io/badge/License-MIT-green)

[English](README.md) | **简体中文**

**TL;DR:** **Google Antigravity** 与 **WorkBuddy** 均未提供常驻桌面的状态小组件，每次查看模型剩余额度、重置倒计时或今日 Token/积分消耗都要切回主窗口。**AI Status Widget** 采用原生 `344×116` **macOS 液态玻璃（Liquid Glass）**桌面底层小组件（`NSPanel`）配合浏览器 **工业风 Web 设置向导**，**100% 本地只读采集**，零外网轮询、零封号风险。

---

## 对比：官方客户端 vs. AI Status Widget

| 特性 | Antigravity / WorkBuddy 官方界面 | AI Status Widget |
| :--- | :--- | :--- |
| **桌面常驻** | 需切换应用窗口或打开网页 | 常驻桌面底层（`level = -2147483602`），不抢焦点不遮挡工作区 |
| **重置倒计时** | 藏在模型设置菜单内 | 顶部胶囊实时每秒倒计时（`3h40m`） |
| **今日 Token 统计** | 无统一双工具汇总视图 | 并排展示两款工具今日 `↑ 输入` / `↓ 输出` Token |
| **WorkBuddy 积分** | 仅云端可见 | 本地 `workbuddy.db` 逐笔扣费 + `main.log` 每日签到自动记账 |
| **账号安全性** | — | 零外网请求，纯本地只读统计，无封号风险 |
| **玻璃视觉** | 常规应用窗口 | 浅/深色自适应 **Liquid Glass**（`NSGlassEffectView` / `NSVisualEffectView`）+ 1px 棱边高光 |

---

## 支持的工具与模型

- **Google Antigravity**（通过本地 `hub_*.json` 引擎与 `brain/*/transcript.jsonl`）：
  - **Gemini 系列**：`Gemini 4 Neon`、`Gemini 4 Carbon`、`Gemini 4 Argon`、`Gemini 4 Hydrogen`、`Gemini 3.8 Flash`、`Orchestrator`（5 小时额度百分比与重置倒计时）
  - **Claude 与 GPT 系列**：`Claude Opus 5.5`、`Claude Sonnet 5.5`、`GPT-OSS 120B`（剩余额度百分比）
  - **今日 Token**：当日估算 `Input` 与 `Output` Token
- **WorkBuddy**（通过只读 `~/.workbuddy/workbuddy.db` 与 `~/.workbuddy/logs/main.log`）：
  - **积分余额与今日消耗**：一次校准当前余额后，自动累加每日签到（`claimDailyCheckin`）并自动扣减每次对话消耗（`session_usage.credit_json`）
  - **今日 Token 与会话数**：当日 `Input` / `Output` Token 与活跃会话数

---

## 安装与构建

### 方式一：下载预编译包（Apple Silicon `arm64`）

1. 前往 [GitHub Releases](../../releases) 下载 `AIStatusWidget-arm64.zip`。
2. 解压后将 `AIStatusWidget.app` 拖入 `/Applications/`。
3. 首次打开前在终端执行以下命令移除隔离属性：

```bash
xattr -cr "/Applications/AIStatusWidget.app"
```

4. 双击 `/Applications/AIStatusWidget.app` 即可运行。

### 方式二：从源码编译

需要 macOS（带 `swiftc` / Xcode Command Line Tools）与 `/usr/bin/python3`。

```bash
git clone https://github.com/ARRIIIIIS/ai-status-widget.git
cd ai-status-widget
./build.sh
open ./AIStatusWidget.app
```

---

## 操作说明

- **防误触拖拽**：在非按钮区域**长按 `0.25s`** 触发拖动，松手自动记忆坐标并在重启时做屏幕边界夹紧。
- **刷新按钮**：点击顶部中央圆形玻璃 `↻` 按钮立即刷新，带焦散光晕反馈。
- **极简菜单栏**：顶部菜单栏仅保留一个图标与 3 项菜单（`Settings Wizard...`、`Restart`、`Quit`），语言随向导页实时切换。
- **工业风 Web 设置向导**：在默认浏览器打开（`http://127.0.0.1:<port>/`），支持 `EN | 中文` 切换、4 格 HUD 遥测条、Antigravity 与 WorkBuddy 分开设置、刷新频率（`15s / 30s / 60s`）及开机自启动。

---

## 常见问题（FAQ）

### 一直运行会触发 WorkBuddy 或 Antigravity 封号吗？
不会。本工具不向任何外部服务器发送轮询请求：WorkBuddy 仅以只读方式读取本地 `workbuddy.db` 与 `main.log`；Antigravity 仅请求本机 `127.0.0.1` 桌面端本地引擎。

### WorkBuddy 没有开放余额接口，怎么自动追踪剩余积分？
WorkBuddy 会将每次对话的积分消耗记录在本地 `workbuddy.db`（带毫秒时间戳），并将每日签到奖励记录在 `main.log`。只需在 Web 向导里填一次当前余额，后续签到自动加分、对话自动扣分。

### 提示“无法打开，因为无法验证开发者”怎么办？
在终端执行 `xattr -cr "/Applications/AIStatusWidget.app"`，或右键该应用选择「打开」。
