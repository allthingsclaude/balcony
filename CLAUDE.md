# CLAUDE.md - Balcony Project Conventions

## Project Overview
Balcony is a companion app system for monitoring and interacting with Claude Code sessions from your iPhone.
It consists of three components: BalconyMac (macOS menu bar agent), BalconyiOS (iPhone app), and BalconyShared (Swift package with shared models, TLS identity, and protocol).

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

# Build BalconyiOS (simulator build needs no signing; deployment target is iOS 26)
xcodebuild -project Balcony.xcodeproj -scheme BalconyiOS -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

## Architecture

### Components
- **BalconyShared/** - Swift Package with models, TLS identity (`Security/TLSIdentity.swift`), parser, protocol definitions
- **BalconyMac/** - macOS menu bar agent (TLS WebSocket server, Bonjour, BLE peripheral, session monitor)
- **BalconyiOS/** - iOS app (WebSocket client w/ cert pinning, Bonjour browser, BLE central, terminal view)

### Key Patterns
- **Concurrency**: Use Swift Concurrency (async/await, Actor, AsyncStream) throughout
- **Observation**: Use @Observable (macOS 14+/iOS 17+) or @ObservableObject for older targets
- **Error Handling**: Use BalconyError enum, log with os.Logger (not print)
- **Networking**: SwiftNIO for WebSocket server (Mac), URLSession for client (iOS)
- **Transport security**: TLS (`wss://`) via NIOSSL on the Mac, using a persistent self-signed cert. The iOS client dials a raw IP, so it authenticates the server by **pinning** the cert's SHA-256 — delivered in the pairing QR (`fp`). See `TLSIdentity` + `WebSocketClient.PinningDelegate`. This is OS/standard TLS only, so the iOS app is export-exempt (`ITSAppUsesNonExemptEncryption=false`).

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
- swift-nio-ssl (2.27+) - TLS for the WebSocket transport (wss)
- swift-nio-transport-services (1.21+) - Network.framework bridge
- swift-certificates (1.0+) / swift-crypto (3.0+) / swift-asn1 (1.0+) - self-signed cert generation + pinning
- SwiftTerm (2.0+) - Terminal rendering (iOS only, Phase 1.8)

## Testing
- Unit tests in BalconyShared/Tests/
- Run: `cd BalconyShared && swift test`
- Test TLS identity/pinning (`TLSIdentityTests`), models, parser, protocol encoding/decoding

## Important Notes
- BalconyMac runs as menu bar agent (LSUIElement = YES)
- WebSocket server port: 29170 (configurable)
- Bonjour service type: _balcony._tcp.
- BLE service UUID: B41C0000-0001-0001-0001-000000000001
- Store the TLS private key + cert (PEM) in the Keychain on the Mac (`KeychainStore`); the cert is long-lived and must be stable, since its pin anchors every pairing. Never log key material.
- Claude Code session files: ~/.claude/projects/{hash}/{id}.jsonl
