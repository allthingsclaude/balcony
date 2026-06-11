# Balcony

Monitor and interact with [Claude Code](https://claude.com/claude-code) sessions from your iPhone — and from a native floating panel on your Mac.

Balcony wraps Claude Code in a PTY, streams the live session to a menu bar agent on your Mac, and mirrors it to your iPhone over your local network with end-to-end encryption. Permission prompts and questions become native UI: respond from the terminal, the Mac panel, or your phone — whichever is closest. The first response wins.

## How it works

```
┌─────────────┐  Unix socket   ┌─────────────┐  WebSocket (E2E)   ┌─────────────┐
│ balcony CLI │ ─────────────▶ │ BalconyMac  │ ─────────────────▶ │ BalconyiOS  │
│ (PTY wrap)  │  ~/.balcony/   │ (menu bar)  │  Bonjour + :29170  │  (iPhone)   │
└─────────────┘                └─────────────┘                    └─────────────┘
       ▲                              ▲
       │ spawns                       │ Claude Code hooks (~/.balcony/hooks.sock)
   claude CLI                     structured prompt data
```

- **`balcony` CLI** — drop-in wrapper: run `balcony` anywhere you'd run `claude` (all arguments pass through). It spawns Claude Code in a PTY and forwards the raw terminal stream to the Mac agent. Works fine even if the agent isn't running.
- **BalconyMac** — menu bar agent. Hosts the WebSocket server, advertises via Bonjour, listens for Claude Code hook events, and shows floating prompt panels.
- **BalconyiOS** — iPhone app. Discovers your Mac on the local network, renders the session as a conversation, and surfaces prompts as native cards.

## Features

- **Live session mirror** — parsed terminal output rendered natively on iPhone, with text input, slash-command and `@`-file menus.
- **Native permission prompts** — Claude Code's `PermissionRequest` hook delivers structured data (tool, command, risk level). The Mac shows a non-activating floating panel; iOS shows an enriched card. Answering anywhere dismisses everywhere.
- **Questions & idle prompts** — `AskUserQuestion` becomes a step-by-step wizard with options and free-text input; when Claude stops and waits, you get an idle prompt with detected options.
- **Native pickers** — `/model`, `/resume`, and `/rewind` open native pickers instead of TUI menus.
- **Mac niceties** — double-tap ⌘ to focus the frontmost prompt panel, hold ⌘ for voice input, keyboard shortcuts on every action, notification sounds.
- **Live Activity** — session status (working / done / needs attention) on the lock screen and Dynamic Island.
- **Proximity awareness** — optional BLE signal between Mac and iPhone for away detection and notifications.
- **End-to-end encryption** — X25519 key exchange + XChaCha20-Poly1305 (libsodium). Keys live in the Keychain.

## Install

### Mac (agent + CLI)

```bash
brew tap allthingsclaude/balcony https://github.com/allthingsclaude/balcony
brew install --cask balcony
```

Or grab the notarized DMG from [Releases](https://github.com/allthingsclaude/balcony/releases). The cask also links the `balcony` CLI into your `PATH`.

On first launch, the setup wizard installs the hook handler to `~/.balcony/` and adds the hook configuration to `~/.claude/settings.json` automatically — no manual hook setup needed. The app updates itself via Sparkle.

### iPhone

The iOS app is distributed through TestFlight / App Store Connect. To build it yourself, see [Build from source](#build-from-source).

### Pairing

1. Launch Balcony on the Mac and open the menu bar popover.
2. On the iPhone, Balcony discovers the Mac via Bonjour — tap it, or scan the QR code shown on the Mac for manual pairing.
3. Run `balcony` in any project. The session appears on both devices.

## Requirements

- macOS 14+ (Sonoma), iOS 16+
- [Claude Code](https://claude.com/claude-code) CLI installed
- Both devices on the same local network (a cloud relay for remote access is planned)

## Build from source

Prerequisites: Xcode 15+, [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/allthingsclaude/balcony.git
cd balcony
xcodegen generate

# Shared package tests
cd BalconyShared && swift test && cd ..

# Mac app
xcodebuild -project Balcony.xcodeproj -scheme BalconyMac -configuration Debug build

# iOS app (requires signing for device installs)
xcodebuild -project Balcony.xcodeproj -scheme BalconyiOS -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 15' build
```

`Scripts/dev.sh` does the kill → regenerate → build → relaunch cycle for the Mac app during development.

## Repository layout

| Path | What it is |
|------|------------|
| `BalconyCLI/` | `balcony` PTY wrapper CLI |
| `BalconyMac/` | macOS menu bar agent |
| `BalconyiOS/` | iPhone app |
| `BalconyShared/` | Swift package: models, protocol, crypto |
| `BalconyLiveActivity/`, `BalconyActivity/` | Live Activity widget extension |
| `Scripts/` | hook handler, release, DMG, notarization scripts |
| `supabase/` | cloud relay scaffold (Phase 2, not yet active) |

## Troubleshooting

- **Prompts don't appear on iPhone/Mac panel** — make sure you launched the session with `balcony` (not bare `claude`), and that the hook entries exist in `~/.claude/settings.json` (re-run the setup from the Mac app's menu if needed).
- **Hook debugging** — set `BALCONY_HOOK_DEBUG=1` in the environment where Claude Code runs to log hook traffic to `/tmp/balcony-hook-debug.log`.
- **iPhone can't find the Mac** — both devices must be on the same network; check that the Mac agent is running (menu bar icon) and that port 29170 isn't blocked.
