# CLAUDE.md - Balcony Project Conventions

## Project Overview
Balcony is a companion app system for monitoring and interacting with Claude Code sessions from your iPhone.
It consists of three components: BalconyMac (macOS menu bar agent), BalconyiOS (iPhone app), and BalconyShared (Swift package with shared models and crypto).

## Build & Run

### Prerequisites
- macOS 14+ (Sonoma)
- Xcode 15+
- Swift 5.9+
- xcodegen (`brew install xcodegen`)

### Build Commands
```bash
# Regenerate Xcode project after changing project.yml
xcodegen generate

# Build BalconyShared package
cd BalconyShared && swift build

# Run BalconyShared tests
cd BalconyShared && swift test

# Build BalconyMac (from Xcode or command line)
xcodebuild -project Balcony.xcodeproj -scheme BalconyMac -configuration Debug build

# Build BalconyiOS (requires signing)
xcodebuild -project Balcony.xcodeproj -scheme BalconyiOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15' build
```

## Architecture

### Components
- **BalconyShared/** - Swift Package with models, crypto, parser, protocol definitions
- **BalconyMac/** - macOS menu bar agent (WebSocket server, Bonjour, BLE peripheral, session monitor)
- **BalconyiOS/** - iOS app (WebSocket client, Bonjour browser, BLE central, terminal view)
- **supabase/** - Cloud relay scaffold (Phase 2)

### Key Patterns
- **Concurrency**: Use Swift Concurrency (async/await, Actor, AsyncStream) throughout
- **Observation**: Use @Observable (macOS 14+/iOS 17+) or @ObservableObject for older targets
- **Error Handling**: Use BalconyError enum, log with os.Logger (not print)
- **Networking**: SwiftNIO for WebSocket server (Mac), URLSession for client (iOS)
- **Encryption**: libsodium via Swift Sodium - X25519 + XChaCha20-Poly1305

### File Organization
- One type per file
- Use `// MARK: -` sections
- All public APIs must have doc comments
- Prefer value types (struct/enum) over classes

## Code Style
- Follow Swift API Design Guidelines
- Use Swift Concurrency over GCD/callbacks
- Actors for thread-safe mutable state
- @MainActor for UI-bound classes
- Result type at API boundaries

## Dependencies (SPM only - no CocoaPods/Carthage)
- swift-nio (2.65+) - WebSocket server
- swift-nio-ssl (2.27+) - TLS
- swift-nio-transport-services (1.21+) - Network.framework bridge
- swift-sodium (0.9.1+) - E2E encryption
- SwiftTerm (2.0+) - Terminal rendering (iOS only, Phase 1.8)

## Testing
- Unit tests in BalconyShared/Tests/
- Run: `cd BalconyShared && swift test`
- Test crypto, models, parser, protocol encoding/decoding

## Important Notes
- BalconyMac runs as menu bar agent (LSUIElement = YES)
- WebSocket server port: 29170 (configurable)
- Bonjour service type: _balcony._tcp.
- BLE service UUID: B41C0000-0001-0001-0001-000000000001
- Store encryption keys in Keychain, never log them
- Claude Code session files: ~/.claude/projects/{hash}/sessions/{id}.jsonl
