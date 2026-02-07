#!/bin/bash
set -euo pipefail

# =============================================================================
# Balcony - Claude Code iOS Companion
# Bootstrap Script
# =============================================================================

# -- Colors & Formatting ------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BALCONY='\033[38;2;217;119;86m' # #D97756
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

step_number=0

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERR]${NC}  $1"; }
step()    { step_number=$((step_number + 1)); echo -e "\n${BOLD}${MAGENTA}[$step_number]${NC} ${BOLD}$1${NC}"; }
detail()  { echo -e "     ${DIM}$1${NC}"; }

# -- Banner -------------------------------------------------------------------
echo -e "${BOLD}${BALCONY}"
echo "  ____        _                        "
echo " | __ )  __ _| | ___ ___  _ __  _   _  "
echo " |  _ \\ / _\` | |/ __/ _ \\| '_ \\| | | | "
echo " | |_) | (_| | | (_| (_) | | | | |_| | "
echo " |____/ \\__,_|_|\\___\\___/|_| |_|\\__, | "
echo "                                 |___/  "
echo -e "${NC}"
echo -e "${DIM}  Claude Code iOS Companion - Bootstrap${NC}"
echo -e "${DIM}  ======================================${NC}\n"

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
info "Project root: ${PROJECT_ROOT}"

# -- Prerequisites Check ------------------------------------------------------
step "Checking prerequisites"

# macOS check
if [[ "$(uname)" != "Darwin" ]]; then
    error "This project requires macOS. Detected: $(uname)"
    exit 1
fi
success "Running on macOS $(sw_vers -productVersion)"

# Xcode check
if ! command -v xcodebuild &> /dev/null; then
    error "Xcode is not installed. Install from the App Store or: xcode-select --install"
    exit 1
fi
XCODE_VERSION=$(xcodebuild -version 2>&1 | head -1 || true)
success "Found $XCODE_VERSION"

# Swift check
if ! command -v swift &> /dev/null; then
    error "Swift is not available. Ensure Xcode command line tools are installed."
    exit 1
fi
SWIFT_VERSION=$(swift --version 2>&1 | head -1 || true)
success "Found Swift: $SWIFT_VERSION"

# Check Swift version >= 5.9
SWIFT_VER_STR=$(swift --version 2>&1 | grep -oE 'Swift version [0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+' || true)
SWIFT_MAJOR=$(echo "$SWIFT_VER_STR" | cut -d. -f1)
SWIFT_MINOR=$(echo "$SWIFT_VER_STR" | cut -d. -f2)
if [[ -z "$SWIFT_MAJOR" ]] || [[ "$SWIFT_MAJOR" -lt 5 ]] || { [[ "$SWIFT_MAJOR" -eq 5 ]] && [[ "$SWIFT_MINOR" -lt 9 ]]; }; then
    error "Swift 5.9+ is required. Found: ${SWIFT_MAJOR:-unknown}.${SWIFT_MINOR:-unknown}"
    exit 1
fi
success "Swift version ${SWIFT_MAJOR}.${SWIFT_MINOR} meets requirement (5.9+)"

# xcodegen check (install if missing)
if ! command -v xcodegen &> /dev/null; then
    warn "xcodegen not found. Installing via Homebrew..."
    if ! command -v brew &> /dev/null; then
        error "Homebrew is required to install xcodegen. Install from https://brew.sh"
        exit 1
    fi
    brew install xcodegen
    if ! command -v xcodegen &> /dev/null; then
        error "Failed to install xcodegen."
        exit 1
    fi
fi
XCODEGEN_VERSION=$(xcodegen --version 2>&1 || echo "unknown")
success "Found xcodegen: $XCODEGEN_VERSION"

# -- Directory Structure -------------------------------------------------------
step "Creating directory structure"

directories=(
    # BalconyShared
    "BalconyShared/Sources/BalconyShared/Models"
    "BalconyShared/Sources/BalconyShared/Protocol"
    "BalconyShared/Sources/BalconyShared/Crypto"
    "BalconyShared/Sources/BalconyShared/Parser"
    "BalconyShared/Sources/BalconyShared/Extensions"
    "BalconyShared/Tests/BalconySharedTests"

    # BalconyMac
    "BalconyMac/Sources/App"
    "BalconyMac/Sources/MenuBar"
    "BalconyMac/Sources/Session"
    "BalconyMac/Sources/Connection"
    "BalconyMac/Sources/Away"
    "BalconyMac/Sources/Preferences"
    "BalconyMac/Resources/Assets.xcassets/AppIcon.appiconset"
    "BalconyMac/Supporting"

    # BalconyiOS
    "BalconyiOS/Sources/App"
    "BalconyiOS/Sources/Views/Discovery"
    "BalconyiOS/Sources/Views/Sessions"
    "BalconyiOS/Sources/Views/Terminal"
    "BalconyiOS/Sources/Views/Settings"
    "BalconyiOS/Sources/Views/Components"
    "BalconyiOS/Sources/Connection"
    "BalconyiOS/Sources/Session"
    "BalconyiOS/Sources/Notifications"
    "BalconyiOS/Resources/Assets.xcassets/AppIcon.appiconset"
    "BalconyiOS/Supporting"

    # Supabase (Phase 2 scaffold)
    "supabase/migrations"
    "supabase/functions/relay-message"
    "supabase/functions/send-push"
    "supabase/functions/cleanup"

    # Claude config
    ".claude/temp"
)

for dir in "${directories[@]}"; do
    mkdir -p "${PROJECT_ROOT}/${dir}"
    detail "Created ${dir}/"
done
success "Directory structure created"

# -- BalconyShared Package.swift -----------------------------------------------
step "Creating BalconyShared Swift Package"

cat > "${PROJECT_ROOT}/BalconyShared/Package.swift" << 'SWIFT_PACKAGE'
// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BalconyShared",
    platforms: [
        .macOS(.v14),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "BalconyShared",
            targets: ["BalconyShared"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.27.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.21.0"),
        .package(url: "https://github.com/jedisct1/swift-sodium.git", from: "0.9.1"),
    ],
    targets: [
        .target(
            name: "BalconyShared",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "Sodium", package: "swift-sodium"),
            ]
        ),
        .testTarget(
            name: "BalconySharedTests",
            dependencies: ["BalconyShared"]
        ),
    ]
)
SWIFT_PACKAGE
success "Created BalconyShared/Package.swift"

# -- BalconyShared Source Files -------------------------------------------------
step "Creating BalconyShared source files"

# Models/Session.swift
cat > "${PROJECT_ROOT}/BalconyShared/Sources/BalconyShared/Models/Session.swift" << 'EOF'
import Foundation

/// Represents a Claude Code session running on the Mac.
public struct Session: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let projectPath: String
    public var status: SessionStatus
    public let createdAt: Date
    public var lastActivityAt: Date
    public var messageCount: Int

    public var projectName: String {
        (projectPath as NSString).lastPathComponent
    }

    public init(
        id: String,
        projectPath: String,
        status: SessionStatus = .active,
        createdAt: Date = Date(),
        lastActivityAt: Date = Date(),
        messageCount: Int = 0
    ) {
        self.id = id
        self.projectPath = projectPath
        self.status = status
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.messageCount = messageCount
    }
}

/// Status of a Claude Code session.
public enum SessionStatus: String, Codable, Sendable {
    case active
    case idle
    case waitingForInput
    case completed
    case error
}
EOF
detail "Created Models/Session.swift"

# Models/SessionMessage.swift
cat > "${PROJECT_ROOT}/BalconyShared/Sources/BalconyShared/Models/SessionMessage.swift" << 'EOF'
import Foundation

/// A single message within a Claude Code session.
public struct SessionMessage: Codable, Identifiable, Sendable {
    public let id: UUID
    public let sessionId: String
    public let role: MessageRole
    public let content: String
    public let timestamp: Date
    public var toolUses: [ToolUse]

    public init(
        id: UUID = UUID(),
        sessionId: String,
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        toolUses: [ToolUse] = []
    ) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolUses = toolUses
    }
}

/// The role of a message sender.
public enum MessageRole: String, Codable, Sendable {
    case human
    case assistant
    case system
    case toolUse = "tool_use"
    case toolResult = "tool_result"
}
EOF
detail "Created Models/SessionMessage.swift"

# Models/ToolUse.swift
cat > "${PROJECT_ROOT}/BalconyShared/Sources/BalconyShared/Models/ToolUse.swift" << 'EOF'
import Foundation

/// Represents a tool invocation by Claude Code.
public struct ToolUse: Codable, Identifiable, Sendable {
    public let id: UUID
    public let toolName: String
    public let input: String
    public var output: String?
    public var status: ToolUseStatus
    public let startedAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        toolName: String,
        input: String,
        output: String? = nil,
        status: ToolUseStatus = .pending,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.input = input
        self.output = output
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

/// Status of a tool invocation.
public enum ToolUseStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
    case denied
}
EOF
detail "Created Models/ToolUse.swift"

# Models/DeviceInfo.swift
cat > "${PROJECT_ROOT}/BalconyShared/Sources/BalconyShared/Models/DeviceInfo.swift" << 'EOF'
import Foundation

/// Identity information for a paired device.
public struct DeviceInfo: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let platform: DevicePlatform
    public let publicKeyFingerprint: String

    public init(
        id: String,
        name: String,
        platform: DevicePlatform,
        publicKeyFingerprint: String
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.publicKeyFingerprint = publicKeyFingerprint
    }
}

/// Platform type for a device.
public enum DevicePlatform: String, Codable, Sendable {
    case macOS
    case iOS
}
EOF
detail "Created Models/DeviceInfo.swift"

# Models/AwayStatus.swift
cat > "${PROJECT_ROOT}/BalconyShared/Sources/BalconyShared/Models/AwayStatus.swift" << 'EOF'
import Foundation

/// User presence state determined by multi-signal away detection.
public enum AwayStatus: String, Codable, Sendable {
    /// User is actively at the Mac.
    case present
    /// User appears idle (no recent input but still nearby).
    case idle
    /// User has left (no BLE signal, no network presence).
    case away
    /// Mac screen is locked.
    case locked
}

/// Raw signals used to determine away status.
public struct AwaySignals: Codable, Sendable {
    /// BLE RSSI in dBm. nil if device not found.
    public var bleRSSI: Int?
    /// Seconds since last keyboard/mouse event.
    public var idleSeconds: Int
    /// Whether the Mac screen is locked.
    public var screenLocked: Bool
    /// Whether the iPhone is visible on the local network.
    public var onLocalNetwork: Bool

    public init(
        bleRSSI: Int? = nil,
        idleSeconds: Int = 0,
        screenLocked: Bool = false,
        onLocalNetwork: Bool = true
    ) {
        self.bleRSSI = bleRSSI
        self.idleSeconds = idleSeconds
        self.screenLocked = screenLocked
        self.onLocalNetwork = onLocalNetwork
    }

    /// Compute the away status from current signals.
    public func computeStatus() -> AwayStatus {
        if screenLocked {
            return .locked
        } else if bleRSSI == nil && !onLocalNetwork {
            return .away
        } else if idleSeconds > 300 || (bleRSSI != nil && bleRSSI! < -80) {
            return .idle
        } else if idleSeconds > 120 {
            return .idle
        } else {
            return .present
        }
    }
}
EOF
detail "Created Models/AwayStatus.swift"

# Models/BalconyMessage.swift
cat > "${PROJECT_ROOT}/BalconyShared/Sources/BalconyShared/Models/BalconyMessage.swift" << 'EOF'
import Foundation

/// Top-level message envelope for all WebSocket communication.
public struct BalconyMessage: Codable, Sendable {
    public let id: UUID
    public let type: MessageType
    public let timestamp: Date
    public let payload: Data

    public init(
        id: UUID = UUID(),
        type: MessageType,
        timestamp: Date = Date(),
        payload: Data
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.payload = payload
    }

    /// Create a message with an Encodable payload.
    public static func create<T: Encodable>(
        type: MessageType,
        payload: T
    ) throws -> BalconyMessage {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return BalconyMessage(type: type, payload: data)
    }

    /// Decode the payload into a specific type.
    public func decodePayload<T: Decodable>(_ type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: payload)
    }
}
EOF
detail "Created Models/BalconyMessage.swift"

# Protocol/MessageType.swift
cat > "${PROJECT_ROOT}/BalconyShared/Sources/BalconyShared/Protocol/MessageType.swift" << 'EOF'
import Foundation

/// All possible message types in the Balcony WebSocket protocol.
public enum MessageType: String, Codable, Sendable {
    // Connection lifecycle
    case handshake
    case handshakeAck
    case ping
    case pong
    case error

    // Session management
    case sessionList
    case sessionUpdate
    case sessionSubscribe
    case sessionUnsubscribe

    // Content streaming
    case terminalOutput
    case userInput

    // Tool use events
    case toolUseStart
    case toolUseEnd

    // Presence
    case awayStatusUpdate
}
EOF
detail "Created Protocol/MessageType.swift"

# Protocol/MessageEncoder.swift
cat > "${PROJECT_ROOT}/BalconyShared/Sources/BalconyShared/Protocol/MessageEncoder.swift" << 'EOF'
import Foundation

/// Encodes BalconyMessage instances for WebSocket transmission.
public struct MessageEncoder: Sendable {
    private let jsonEncoder: JSONEncoder

    public init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [] // compact JSON
        self.jsonEncoder = encoder
    }

    /// Encode a message to JSON data.
    public func encode(_ message: BalconyMessage) throws -> Data {
        try jsonEncoder.encode(message)
    }

    /// Encode a message to a UTF-8 string.
    public func encodeToString(_ message: BalconyMessage) throws -> String {
        let data = try encode(message)
        guard let string = String(data: data, encoding: .utf8) else {
            throw BalconyError.encodingFailed("Failed to convert message data to UTF-8 string")
        }
        return string
    }
}
EOF
detail "Created Protocol/MessageEncoder.swift"

# Protocol/MessageDecoder.swift
cat > "${PROJECT_ROOT}/BalconyShared/Sources/BalconyShared/Protocol/MessageDecoder.swift" << 'EOF'
import Foundation

/// Decodes BalconyMessage instances from WebSocket data.
public struct MessageDecoder: Sendable {
    private let jsonDecoder: JSONDecoder

    public init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.jsonDecoder = decoder
    }

    /// Decode a message from JSON data.
    public func decode(_ data: Data) throws -> BalconyMessage {
        try jsonDecoder.decode(BalconyMessage.self, from: data)
    }

    /// Decode a message from a UTF-8 string.
    public func decode(_ string: String) throws -> BalconyMessage {
        guard let data = string.data(using: .utf8) else {
            throw BalconyError.decodingFailed("Failed to convert string to UTF-8 data")
        }
        return try decode(data)
    }
}
EOF
detail "Created Protocol/MessageDecoder.swift"

# Crypto/CryptoManager.swift
cat > "${PROJECT_ROOT}/BalconyShared/Sources/BalconyShared/Crypto/CryptoManager.swift" << 'EOF'
import Foundation
import Sodium

/// Manages E2E encryption using X25519 key exchange and XChaCha20-Poly1305.
public actor CryptoManager {
    private let sodium = Sodium()
    private var keyPair: KeyPair?
    private var sharedSecret: Bytes?
    private var nonceCounter: UInt64 = 0

    public init() {}

    // MARK: - Key Generation

    /// Generate a new X25519 key pair for this device.
    public func generateKeyPair() throws -> KeyPair {
        guard let kp = sodium.box.keyPair() else {
            throw BalconyError.cryptoError("Failed to generate key pair")
        }
        let pair = KeyPair(publicKey: kp.publicKey, secretKey: kp.secretKey)
        self.keyPair = pair
        return pair
    }

    /// Get the public key as Base64 for QR code display.
    public func publicKeyBase64() throws -> String {
        guard let kp = keyPair else {
            throw BalconyError.cryptoError("No key pair generated")
        }
        return Data(kp.publicKey).base64EncodedString()
    }

    // MARK: - Key Exchange

    /// Derive shared secret from our private key and their public key.
    public func deriveSharedSecret(theirPublicKey: Bytes) throws {
        guard let kp = keyPair else {
            throw BalconyError.cryptoError("No key pair generated")
        }
        guard let secret = sodium.box.beforenm(
            recipientPublicKey: theirPublicKey,
            senderSecretKey: kp.secretKey
        ) else {
            throw BalconyError.cryptoError("Failed to derive shared secret")
        }
        self.sharedSecret = secret
    }

    // MARK: - Encryption / Decryption

    /// Encrypt plaintext data using XChaCha20-Poly1305.
    public func encrypt(_ plaintext: Data) throws -> Data {
        guard let secret = sharedSecret else {
            throw BalconyError.cryptoError("No shared secret established")
        }

        let nonce = generateNonce()
        guard let ciphertext = sodium.secretBox.seal(
            message: Bytes(plaintext),
            secretKey: secret,
            nonce: nonce
        ) else {
            throw BalconyError.cryptoError("Encryption failed")
        }

        // Prepend nonce to ciphertext
        return Data(nonce + ciphertext)
    }

    /// Decrypt ciphertext data using XChaCha20-Poly1305.
    public func decrypt(_ data: Data) throws -> Data {
        guard let secret = sharedSecret else {
            throw BalconyError.cryptoError("No shared secret established")
        }

        let bytes = Bytes(data)
        let nonceSize = sodium.secretBox.NonceBytes
        guard bytes.count > nonceSize else {
            throw BalconyError.cryptoError("Data too short to contain nonce")
        }

        let nonce = Array(bytes[0..<nonceSize])
        let ciphertext = Array(bytes[nonceSize...])

        guard let plaintext = sodium.secretBox.open(
            authenticatedCipherText: ciphertext,
            secretKey: secret,
            nonce: nonce
        ) else {
            throw BalconyError.cryptoError("Decryption failed - invalid ciphertext or wrong key")
        }

        return Data(plaintext)
    }

    // MARK: - Private

    private func generateNonce() -> Bytes {
        nonceCounter += 1
        var nonce = Bytes(repeating: 0, count: sodium.secretBox.NonceBytes)
        var counter = nonceCounter
        for i in 0..<8 {
            nonce[i] = UInt8(counter & 0xFF)
            counter >>= 8
        }
        return nonce
    }
}
EOF
detail "Created Crypto/CryptoManager.swift"

# Crypto/KeyPair.swift
cat > "${PROJECT_ROOT}/BalconyShared/Sources/BalconyShared/Crypto/KeyPair.swift" << 'EOF'
import Foundation
import Sodium

/// An X25519 key pair for E2E encryption.
public struct KeyPair: Sendable {
    public let publicKey: Bytes
    public let secretKey: Bytes

    public init(publicKey: Bytes, secretKey: Bytes) {
        self.publicKey = publicKey
        self.secretKey = secretKey
    }

    /// SHA256 fingerprint of the public key (first 8 bytes, hex-encoded).
    public var fingerprint: String {
        let data = Data(publicKey)
        // Simple hash for fingerprint display
        var hash: UInt64 = 0
        for byte in data {
            hash = hash &* 31 &+ UInt64(byte)
        }
        return String(format: "%016llx", hash)
    }
}
EOF
detail "Created Crypto/KeyPair.swift"

# Parser/JSONLParser.swift
cat > "${PROJECT_ROOT}/BalconyShared/Sources/BalconyShared/Parser/JSONLParser.swift" << 'EOF'
import Foundation

/// Stream-based parser for Claude Code JSONL session files.
public struct JSONLParser: Sendable {
    private let decoder: JSONDecoder

    public init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Parse all complete lines from JSONL data.
    /// Skips malformed lines and incomplete trailing lines.
    public func parse(_ data: Data) -> [SessionMessage] {
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return parse(text)
    }

    /// Parse all complete lines from a JSONL string.
    public func parse(_ text: String) -> [SessionMessage] {
        text
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line in
                parseLine(line)
            }
    }

    /// Parse a single JSONL line into a SessionMessage.
    public func parseLine(_ line: String) -> SessionMessage? {
        guard let data = line.data(using: .utf8) else { return nil }

        do {
            // Try direct decoding first
            return try decoder.decode(SessionMessage.self, from: data)
        } catch {
            // Try parsing as raw JSON and mapping fields
            return parseRawLine(data)
        }
    }

    /// Attempt to parse a line as raw JSON and map to SessionMessage.
    private func parseRawLine(_ data: Data) -> SessionMessage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard let typeStr = json["type"] as? String,
              let role = MessageRole(rawValue: typeStr) else {
            return nil
        }

        let content: String
        if let c = json["content"] as? String {
            content = c
        } else if let c = json["content"] as? [[String: Any]] {
            // Claude API format: content is array of blocks
            content = c.compactMap { $0["text"] as? String }.joined(separator: "\n")
        } else {
            content = ""
        }

        let sessionId = json["session_id"] as? String ?? "unknown"
        let timestamp: Date
        if let ts = json["timestamp"] as? String {
            timestamp = ISO8601DateFormatter().date(from: ts) ?? Date()
        } else {
            timestamp = Date()
        }

        return SessionMessage(
            sessionId: sessionId,
            role: role,
            content: content,
            timestamp: timestamp
        )
    }
}
EOF
detail "Created Parser/JSONLParser.swift"

# Extensions/Data+Hex.swift
cat > "${PROJECT_ROOT}/BalconyShared/Sources/BalconyShared/Extensions/Data+Hex.swift" << 'EOF'
import Foundation

extension Data {
    /// Convert data to a hex-encoded string.
    public var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// Initialize data from a hex-encoded string.
    public init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex
        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
EOF
detail "Created Extensions/Data+Hex.swift"

# Extensions/Date+ISO8601.swift
cat > "${PROJECT_ROOT}/BalconyShared/Sources/BalconyShared/Extensions/Date+ISO8601.swift" << 'EOF'
import Foundation

extension Date {
    /// Format date as ISO 8601 string.
    public var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }

    /// Parse an ISO 8601 string into a Date.
    public static func fromISO8601(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }
}
EOF
detail "Created Extensions/Date+ISO8601.swift"

# BalconyError (top-level file)
cat > "${PROJECT_ROOT}/BalconyShared/Sources/BalconyShared/BalconyError.swift" << 'EOF'
import Foundation

/// Domain errors for the Balcony app.
public enum BalconyError: LocalizedError, Sendable {
    case connectionFailed(String)
    case cryptoError(String)
    case encodingFailed(String)
    case decodingFailed(String)
    case sessionNotFound(String)
    case hookError(String)
    case fileSystemError(String)
    case timeout(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .cryptoError(let msg): return "Crypto error: \(msg)"
        case .encodingFailed(let msg): return "Encoding failed: \(msg)"
        case .decodingFailed(let msg): return "Decoding failed: \(msg)"
        case .sessionNotFound(let msg): return "Session not found: \(msg)"
        case .hookError(let msg): return "Hook error: \(msg)"
        case .fileSystemError(let msg): return "File system error: \(msg)"
        case .timeout(let msg): return "Timeout: \(msg)"
        case .unknown(let msg): return "Unknown error: \(msg)"
        }
    }
}
EOF
detail "Created BalconyError.swift"

success "BalconyShared source files created"

# -- BalconyShared Tests -------------------------------------------------------
step "Creating BalconyShared test files"

cat > "${PROJECT_ROOT}/BalconyShared/Tests/BalconySharedTests/ModelTests.swift" << 'EOF'
import XCTest
@testable import BalconyShared

final class ModelTests: XCTestCase {

    func testSessionEncoding() throws {
        let session = Session(
            id: "test-123",
            projectPath: "/Users/dev/projects/myapp",
            status: .active
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Session.self, from: data)

        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.projectPath, session.projectPath)
        XCTAssertEqual(decoded.projectName, "myapp")
        XCTAssertEqual(decoded.status, .active)
    }

    func testSessionMessageEncoding() throws {
        let message = SessionMessage(
            sessionId: "test-123",
            role: .assistant,
            content: "Hello, world!"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionMessage.self, from: data)

        XCTAssertEqual(decoded.role, .assistant)
        XCTAssertEqual(decoded.content, "Hello, world!")
    }

    func testAwaySignalsComputation() {
        // Present
        var signals = AwaySignals(bleRSSI: -40, idleSeconds: 10, screenLocked: false, onLocalNetwork: true)
        XCTAssertEqual(signals.computeStatus(), .present)

        // Idle (high idle time)
        signals = AwaySignals(bleRSSI: -40, idleSeconds: 130, screenLocked: false, onLocalNetwork: true)
        XCTAssertEqual(signals.computeStatus(), .idle)

        // Locked
        signals = AwaySignals(bleRSSI: -40, idleSeconds: 10, screenLocked: true, onLocalNetwork: true)
        XCTAssertEqual(signals.computeStatus(), .locked)

        // Away
        signals = AwaySignals(bleRSSI: nil, idleSeconds: 10, screenLocked: false, onLocalNetwork: false)
        XCTAssertEqual(signals.computeStatus(), .away)
    }
}
EOF
detail "Created ModelTests.swift"

cat > "${PROJECT_ROOT}/BalconyShared/Tests/BalconySharedTests/CryptoManagerTests.swift" << 'EOF'
import XCTest
@testable import BalconyShared

final class CryptoManagerTests: XCTestCase {

    func testKeyPairGeneration() async throws {
        let crypto = CryptoManager()
        let keyPair = try await crypto.generateKeyPair()

        XCTAssertFalse(keyPair.publicKey.isEmpty)
        XCTAssertFalse(keyPair.secretKey.isEmpty)
    }

    func testPublicKeyBase64() async throws {
        let crypto = CryptoManager()
        _ = try await crypto.generateKeyPair()
        let base64 = try await crypto.publicKeyBase64()

        XCTAssertFalse(base64.isEmpty)
        XCTAssertNotNil(Data(base64Encoded: base64))
    }

    func testEncryptDecryptRoundTrip() async throws {
        // Simulate two devices
        let alice = CryptoManager()
        let bob = CryptoManager()

        let aliceKP = try await alice.generateKeyPair()
        let bobKP = try await bob.generateKeyPair()

        // Key exchange
        try await alice.deriveSharedSecret(theirPublicKey: bobKP.publicKey)
        try await bob.deriveSharedSecret(theirPublicKey: aliceKP.publicKey)

        // Encrypt on Alice's side
        let plaintext = "Hello from Alice!".data(using: .utf8)!
        let ciphertext = try await alice.encrypt(plaintext)

        // Decrypt on Bob's side
        let decrypted = try await bob.decrypt(ciphertext)

        XCTAssertEqual(String(data: decrypted, encoding: .utf8), "Hello from Alice!")
    }
}
EOF
detail "Created CryptoManagerTests.swift"

cat > "${PROJECT_ROOT}/BalconyShared/Tests/BalconySharedTests/JSONLParserTests.swift" << 'EOF'
import XCTest
@testable import BalconyShared

final class JSONLParserTests: XCTestCase {

    func testParseValidLines() {
        let parser = JSONLParser()
        let jsonl = """
        {"type":"human","content":"Hello","session_id":"s1","timestamp":"2024-01-01T00:00:00Z"}
        {"type":"assistant","content":"Hi there!","session_id":"s1","timestamp":"2024-01-01T00:00:01Z"}
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .human)
        XCTAssertEqual(messages[1].role, .assistant)
    }

    func testSkipMalformedLines() {
        let parser = JSONLParser()
        let jsonl = """
        {"type":"human","content":"Hello","session_id":"s1","timestamp":"2024-01-01T00:00:00Z"}
        {invalid json here
        {"type":"assistant","content":"World","session_id":"s1","timestamp":"2024-01-01T00:00:01Z"}
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 2)
    }

    func testEmptyInput() {
        let parser = JSONLParser()
        let messages = parser.parse("")
        XCTAssertEqual(messages.count, 0)
    }
}
EOF
detail "Created JSONLParserTests.swift"

cat > "${PROJECT_ROOT}/BalconyShared/Tests/BalconySharedTests/MessageProtocolTests.swift" << 'EOF'
import XCTest
@testable import BalconyShared

final class MessageProtocolTests: XCTestCase {

    func testMessageEncodeDecode() throws {
        let encoder = MessageEncoder()
        let decoder = MessageDecoder()

        let session = Session(id: "s1", projectPath: "/test")
        let message = try BalconyMessage.create(type: .sessionUpdate, payload: session)

        let encoded = try encoder.encode(message)
        let decoded = try decoder.decode(encoded)

        XCTAssertEqual(decoded.type, .sessionUpdate)
        XCTAssertEqual(decoded.id, message.id)

        let decodedSession = try decoded.decodePayload(Session.self)
        XCTAssertEqual(decodedSession.id, "s1")
    }

    func testMessageStringRoundTrip() throws {
        let encoder = MessageEncoder()
        let decoder = MessageDecoder()

        let payload = "test".data(using: .utf8)!
        let message = BalconyMessage(type: .ping, payload: payload)

        let string = try encoder.encodeToString(message)
        let decoded = try decoder.decode(string)

        XCTAssertEqual(decoded.type, .ping)
    }
}
EOF
detail "Created MessageProtocolTests.swift"

success "BalconyShared test files created"

# -- BalconyMac Source Files ----------------------------------------------------
step "Creating BalconyMac source files"

# App/BalconyMacApp.swift
cat > "${PROJECT_ROOT}/BalconyMac/Sources/App/BalconyMacApp.swift" << 'EOF'
import SwiftUI
import BalconyShared

@main
struct BalconyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Balcony", systemImage: "antenna.radiowaves.left.and.right") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
        }
    }
}
EOF
detail "Created App/BalconyMacApp.swift"

# App/AppDelegate.swift
cat > "${PROJECT_ROOT}/BalconyMac/Sources/App/AppDelegate.swift" << 'EOF'
import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("BalconyMac launched")
        // TODO: Initialize SessionMonitor
        // TODO: Start WebSocket server
        // TODO: Start Bonjour advertiser
        // TODO: Start BLE peripheral
        // TODO: Install Claude Code hooks
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("BalconyMac terminating")
        // TODO: Clean up hooks
        // TODO: Stop servers
    }
}
EOF
detail "Created App/AppDelegate.swift"

# MenuBar/MenuBarView.swift
cat > "${PROJECT_ROOT}/BalconyMac/Sources/MenuBar/MenuBarView.swift" << 'EOF'
import SwiftUI

struct MenuBarView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                Text("Balcony")
                    .font(.headline)
                Spacer()
                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Connected Devices
            Section("Devices") {
                Text("No devices connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Active Sessions
            Section("Sessions") {
                Text("No active sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Actions
            Button("Pair New Device...") {
                // TODO: Show QR code pairing view
            }

            Button("Preferences...") {
                // TODO: Open preferences window
            }

            Divider()

            Button("Quit Balcony") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 280)
    }
}
EOF
detail "Created MenuBar/MenuBarView.swift"

# MenuBar/StatusItemManager.swift
cat > "${PROJECT_ROOT}/BalconyMac/Sources/MenuBar/StatusItemManager.swift" << 'EOF'
import AppKit
import os

/// Manages the menu bar status item icon and state.
@MainActor
final class StatusItemManager: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "StatusItem")

    enum ConnectionState {
        case disconnected
        case connected
        case active
    }

    @Published var connectionState: ConnectionState = .disconnected

    var statusIconName: String {
        switch connectionState {
        case .disconnected: return "antenna.radiowaves.left.and.right.slash"
        case .connected: return "antenna.radiowaves.left.and.right"
        case .active: return "antenna.radiowaves.left.and.right.circle.fill"
        }
    }
}
EOF
detail "Created MenuBar/StatusItemManager.swift"

# MenuBar/QRCodeView.swift
cat > "${PROJECT_ROOT}/BalconyMac/Sources/MenuBar/QRCodeView.swift" << 'EOF'
import SwiftUI
import CoreImage.CIFilterBuiltins

/// Displays a QR code for device pairing.
struct QRCodeView: View {
    let pairingURL: String

    var body: some View {
        VStack(spacing: 16) {
            Text("Scan with Balcony on iPhone")
                .font(.headline)

            if let image = generateQRCode(from: pairingURL) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 200, height: 200)
            } else {
                Text("Failed to generate QR code")
                    .foregroundStyle(.red)
            }

            Text(pairingURL)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding()
    }

    private func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
    }
}
EOF
detail "Created MenuBar/QRCodeView.swift"

# Session/SessionMonitor.swift
cat > "${PROJECT_ROOT}/BalconyMac/Sources/Session/SessionMonitor.swift" << 'EOF'
import Foundation
import BalconyShared
import os

/// Monitors Claude Code session files via FSEvents.
actor SessionMonitor {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "SessionMonitor")
    private let parser = JSONLParser()

    private var sessions: [String: Session] = [:]
    private var fileOffsets: [String: UInt64] = [:]
    private var isMonitoring = false

    private let claudeDir: String

    init(claudeDir: String = "\(NSHomeDirectory())/.claude") {
        self.claudeDir = claudeDir
    }

    // MARK: - Public API

    /// Start monitoring Claude Code session directory.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        logger.info("Started monitoring: \(self.claudeDir)")
        // TODO: Set up FSEvents or DispatchSource for directory monitoring
        // TODO: Scan existing session files
    }

    /// Stop monitoring.
    func stopMonitoring() {
        isMonitoring = false
        logger.info("Stopped monitoring")
    }

    /// Get all known sessions.
    func getSessions() -> [Session] {
        Array(sessions.values).sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    /// Read new content from a session file.
    func readNewContent(sessionId: String, filePath: String) -> [SessionMessage] {
        guard let data = FileManager.default.contents(atPath: filePath) else {
            return []
        }

        let offset = fileOffsets[sessionId] ?? 0
        guard UInt64(data.count) > offset else { return [] }

        let newData = data.subdata(in: Int(offset)..<data.count)
        fileOffsets[sessionId] = UInt64(data.count)

        return parser.parse(newData)
    }
}
EOF
detail "Created Session/SessionMonitor.swift"

# Session/HookManager.swift
cat > "${PROJECT_ROOT}/BalconyMac/Sources/Session/HookManager.swift" << 'EOF'
import Foundation
import os

/// Manages Claude Code hooks for BalconyMac integration.
actor HookManager {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "HookManager")
    private let hooksDir: String

    init(hooksDir: String = "\(NSHomeDirectory())/.claude/hooks") {
        self.hooksDir = hooksDir
    }

    /// Install Balcony hooks into Claude Code hooks directory.
    func installHooks() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)

        let hooks = ["PreToolUse", "PostToolUse", "Notification", "Stop"]
        for hookName in hooks {
            let hookPath = "\(hooksDir)/\(hookName).sh"
            if !fm.fileExists(atPath: hookPath) {
                let script = generateHookScript(name: hookName)
                try script.write(toFile: hookPath, atomically: true, encoding: .utf8)
                // Make executable
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookPath)
                logger.info("Installed hook: \(hookName)")
            }
        }
    }

    /// Remove Balcony hooks.
    func removeHooks() throws {
        let fm = FileManager.default
        let hooks = ["PreToolUse", "PostToolUse", "Notification", "Stop"]
        for hookName in hooks {
            let hookPath = "\(hooksDir)/\(hookName).sh"
            if fm.fileExists(atPath: hookPath) {
                try fm.removeItem(atPath: hookPath)
                logger.info("Removed hook: \(hookName)")
            }
        }
    }

    private func generateHookScript(name: String) -> String {
        """
        #!/bin/bash
        # Balcony Claude Code Hook: \(name)
        # This hook forwards events to the BalconyMac agent.
        # Auto-generated - do not edit manually.

        SOCKET="/tmp/balcony.sock"
        if [ -S "$SOCKET" ]; then
            echo "{\\"hook\\": \\"\(name)\\", \\"data\\": $(cat -)}" | nc -U "$SOCKET" 2>/dev/null || true
        fi
        """
    }
}
EOF
detail "Created Session/HookManager.swift"

# Connection/WebSocketServer.swift
cat > "${PROJECT_ROOT}/BalconyMac/Sources/Connection/WebSocketServer.swift" << 'EOF'
import Foundation
import NIO
import NIOHTTP1
import NIOWebSocket
import BalconyShared
import os

/// WebSocket server for iOS client connections.
actor WebSocketServer {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "WebSocketServer")
    private var group: EventLoopGroup?
    private var channel: Channel?
    private let port: Int

    init(port: Int = 29170) {
        self.port = port
    }

    /// Start the WebSocket server.
    func start() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        self.group = group

        logger.info("Starting WebSocket server on port \(self.port)")

        // TODO: Configure SwiftNIO channel pipeline
        // 1. HTTP server handler
        // 2. WebSocket upgrade handler
        // 3. WebSocket frame handler
        // 4. Message routing to SessionMonitor

        logger.info("WebSocket server started on port \(self.port)")
    }

    /// Stop the WebSocket server.
    func stop() async throws {
        try await channel?.close()
        try await group?.shutdownGracefully()
        logger.info("WebSocket server stopped")
    }
}
EOF
detail "Created Connection/WebSocketServer.swift"

# Connection/BonjourAdvertiser.swift
cat > "${PROJECT_ROOT}/BalconyMac/Sources/Connection/BonjourAdvertiser.swift" << 'EOF'
import Foundation
import Network
import os

/// Advertises the BalconyMac service via Bonjour for zero-config discovery.
actor BonjourAdvertiser {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "BonjourAdvertiser")
    private var listener: NWListener?
    private let port: UInt16
    private let deviceName: String

    init(port: UInt16 = 29170, deviceName: String = Host.current().localizedName ?? "Mac") {
        self.port = port
        self.deviceName = deviceName
    }

    /// Start advertising the Balcony service.
    func startAdvertising(publicKeyFingerprint: String) throws {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)

        let txtRecord = NWTXTRecord()
        // TODO: Set TXT record fields: v, name, pk

        listener.service = NWListener.Service(
            name: deviceName,
            type: "_balcony._tcp."
        )

        listener.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleStateUpdate(state)
            }
        }

        listener.start(queue: .global())
        self.listener = listener
        logger.info("Started Bonjour advertising: _balcony._tcp.")
    }

    /// Stop advertising.
    func stopAdvertising() {
        listener?.cancel()
        listener = nil
        logger.info("Stopped Bonjour advertising")
    }

    private func handleStateUpdate(_ state: NWListener.State) {
        switch state {
        case .ready:
            logger.info("Bonjour listener ready")
        case .failed(let error):
            logger.error("Bonjour listener failed: \(error.localizedDescription)")
        case .cancelled:
            logger.info("Bonjour listener cancelled")
        default:
            break
        }
    }
}
EOF
detail "Created Connection/BonjourAdvertiser.swift"

# Connection/BLEPeripheral.swift
cat > "${PROJECT_ROOT}/BalconyMac/Sources/Connection/BLEPeripheral.swift" << 'EOF'
import Foundation
import CoreBluetooth
import os

/// BLE Peripheral for proximity detection by iOS clients.
final class BLEPeripheral: NSObject, ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "BLEPeripheral")
    private var peripheralManager: CBPeripheralManager?

    /// Custom Balcony BLE service UUID.
    static let serviceUUID = CBUUID(string: "B41C0000-0001-0001-0001-000000000001")
    static let deviceCharacteristicUUID = CBUUID(string: "B41C0001-0001-0001-0001-000000000001")

    override init() {
        super.init()
    }

    /// Start advertising as a BLE peripheral.
    func startAdvertising(deviceName: String) {
        peripheralManager = CBPeripheralManager(delegate: self, queue: .global())
        logger.info("BLE peripheral manager initialized")
    }

    /// Stop advertising.
    func stopAdvertising() {
        peripheralManager?.stopAdvertising()
        peripheralManager = nil
        logger.info("BLE peripheral stopped")
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEPeripheral: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            logger.info("BLE powered on - setting up services")
            // TODO: Add Balcony service and characteristics
            // TODO: Start advertising
        case .poweredOff:
            logger.warning("BLE powered off")
        case .unauthorized:
            logger.warning("BLE unauthorized")
        default:
            break
        }
    }
}
EOF
detail "Created Connection/BLEPeripheral.swift"

# Connection/ConnectionManager.swift
cat > "${PROJECT_ROOT}/BalconyMac/Sources/Connection/ConnectionManager.swift" << 'EOF'
import Foundation
import BalconyShared
import os

/// Coordinates all connection components (WebSocket, Bonjour, BLE).
@MainActor
final class ConnectionManager: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "ConnectionManager")

    @Published var connectedDevices: [DeviceInfo] = []
    @Published var isServerRunning = false

    private let webSocketServer: WebSocketServer
    private let bonjourAdvertiser: BonjourAdvertiser
    private let blePeripheral: BLEPeripheral
    private let cryptoManager: CryptoManager

    init(
        port: Int = 29170
    ) {
        self.webSocketServer = WebSocketServer(port: port)
        self.bonjourAdvertiser = BonjourAdvertiser(port: UInt16(port))
        self.blePeripheral = BLEPeripheral()
        self.cryptoManager = CryptoManager()
    }

    /// Start all connection services.
    func start() async throws {
        logger.info("Starting connection services")

        // Generate encryption keys
        let keyPair = try await cryptoManager.generateKeyPair()
        let fingerprint = keyPair.fingerprint

        // Start WebSocket server
        try await webSocketServer.start()

        // Start Bonjour advertising
        try await bonjourAdvertiser.startAdvertising(publicKeyFingerprint: fingerprint)

        // Start BLE peripheral
        blePeripheral.startAdvertising(deviceName: Host.current().localizedName ?? "Mac")

        isServerRunning = true
        logger.info("All connection services started")
    }

    /// Stop all connection services.
    func stop() async throws {
        try await webSocketServer.stop()
        await bonjourAdvertiser.stopAdvertising()
        blePeripheral.stopAdvertising()
        isServerRunning = false
        logger.info("All connection services stopped")
    }
}
EOF
detail "Created Connection/ConnectionManager.swift"

# Away/AwayDetector.swift
cat > "${PROJECT_ROOT}/BalconyMac/Sources/Away/AwayDetector.swift" << 'EOF'
import Foundation
import BalconyShared
import os

/// Detects user presence using multiple signals.
@MainActor
final class AwayDetector: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "AwayDetector")

    @Published var currentStatus: AwayStatus = .present
    @Published var currentSignals = AwaySignals()

    private var pollTimer: Timer?

    /// Start polling for away signals.
    func startDetecting(interval: TimeInterval = 10.0) {
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateSignals()
            }
        }
        logger.info("Away detection started (interval: \(interval)s)")
    }

    /// Stop polling.
    func stopDetecting() {
        pollTimer?.invalidate()
        pollTimer = nil
        logger.info("Away detection stopped")
    }

    private func updateSignals() {
        // TODO: Read system idle time from CGEventSource
        // TODO: Check screen lock state via DistributedNotificationCenter
        // TODO: Get BLE RSSI from connected iOS device
        // TODO: Check if iOS device is on local network

        // Placeholder values
        currentSignals = AwaySignals(
            bleRSSI: nil,
            idleSeconds: 0,
            screenLocked: false,
            onLocalNetwork: true
        )

        let newStatus = currentSignals.computeStatus()
        if newStatus != currentStatus {
            logger.info("Away status changed: \(String(describing: self.currentStatus)) -> \(String(describing: newStatus))")
            currentStatus = newStatus
        }
    }
}
EOF
detail "Created Away/AwayDetector.swift"

# Preferences/PreferencesView.swift
cat > "${PROJECT_ROOT}/BalconyMac/Sources/Preferences/PreferencesView.swift" << 'EOF'
import SwiftUI

struct PreferencesView: View {
    @AppStorage("wsPort") private var wsPort = 29170
    @AppStorage("autoStart") private var autoStart = true
    @AppStorage("idleThreshold") private var idleThreshold = 120
    @AppStorage("awayThreshold") private var awayThreshold = 300

    var body: some View {
        TabView {
            // General
            Form {
                Section("Server") {
                    TextField("WebSocket Port", value: $wsPort, format: .number)
                    Toggle("Start at login", isOn: $autoStart)
                }
            }
            .tabItem { Label("General", systemImage: "gear") }
            .frame(width: 400, height: 200)

            // Away Detection
            Form {
                Section("Away Detection") {
                    Stepper("Idle threshold: \(idleThreshold)s", value: $idleThreshold, in: 30...600, step: 30)
                    Stepper("Away threshold: \(awayThreshold)s", value: $awayThreshold, in: 60...1800, step: 60)
                }
            }
            .tabItem { Label("Away Detection", systemImage: "person.wave.2") }
            .frame(width: 400, height: 200)
        }
    }
}
EOF
detail "Created Preferences/PreferencesView.swift"

# Preferences/PreferencesManager.swift
cat > "${PROJECT_ROOT}/BalconyMac/Sources/Preferences/PreferencesManager.swift" << 'EOF'
import Foundation
import os

/// Manages persistent preferences for BalconyMac.
final class PreferencesManager: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "Preferences")

    static let shared = PreferencesManager()

    @Published var wsPort: Int {
        didSet { UserDefaults.standard.set(wsPort, forKey: "wsPort") }
    }

    @Published var autoStart: Bool {
        didSet { UserDefaults.standard.set(autoStart, forKey: "autoStart") }
    }

    private init() {
        self.wsPort = UserDefaults.standard.integer(forKey: "wsPort")
        if self.wsPort == 0 { self.wsPort = 29170 }
        self.autoStart = UserDefaults.standard.bool(forKey: "autoStart")
    }
}
EOF
detail "Created Preferences/PreferencesManager.swift"

success "BalconyMac source files created"

# -- BalconyMac Resources -------------------------------------------------------
step "Creating BalconyMac resources"

# Info.plist
cat > "${PROJECT_ROOT}/BalconyMac/Resources/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>BalconyMac</string>
    <key>CFBundleDisplayName</key>
    <string>Balcony</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Balcony uses Bluetooth to detect when your iPhone is nearby for away detection.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Balcony uses the local network to connect to your iPhone.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_balcony._tcp.</string>
    </array>
</dict>
</plist>
EOF
detail "Created Info.plist"

# Entitlements
cat > "${PROJECT_ROOT}/BalconyMac/Resources/BalconyMac.entitlements" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
    <key>com.apple.security.device.bluetooth</key>
    <true/>
</dict>
</plist>
EOF
detail "Created BalconyMac.entitlements"

# AppIcon Contents.json
cat > "${PROJECT_ROOT}/BalconyMac/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json" << 'EOF'
{
  "images" : [
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

# Assets.xcassets Contents.json
cat > "${PROJECT_ROOT}/BalconyMac/Resources/Assets.xcassets/Contents.json" << 'EOF'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
detail "Created Assets.xcassets"

success "BalconyMac resources created"

# -- BalconyiOS Source Files ----------------------------------------------------
step "Creating BalconyiOS source files"

# App/BalconyiOSApp.swift
cat > "${PROJECT_ROOT}/BalconyiOS/Sources/App/BalconyiOSApp.swift" << 'EOF'
import SwiftUI
import BalconyShared

@main
struct BalconyiOSApp: App {
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var sessionManager = SessionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectionManager)
                .environmentObject(sessionManager)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        NavigationStack {
            if connectionManager.isConnected {
                SessionListView()
            } else {
                DiscoveryView()
            }
        }
    }
}
EOF
detail "Created App/BalconyiOSApp.swift"

# Views/Discovery/DiscoveryView.swift
cat > "${PROJECT_ROOT}/BalconyiOS/Sources/Views/Discovery/DiscoveryView.swift" << 'EOF'
import SwiftUI

struct DiscoveryView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Searching for Macs...")
                .font(.title2)

            if connectionManager.discoveredDevices.isEmpty {
                ProgressView()
                    .padding()
                Text("Make sure BalconyMac is running\non your Mac")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                List(connectionManager.discoveredDevices, id: \.id) { device in
                    Button {
                        Task {
                            await connectionManager.connect(to: device)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "desktopcomputer")
                            Text(device.name)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }

            Spacer()

            Button("Scan QR Code") {
                // TODO: Present QR scanner
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Balcony")
        .onAppear {
            connectionManager.startDiscovery()
        }
    }
}
EOF
detail "Created Views/Discovery/DiscoveryView.swift"

# Views/Discovery/QRScannerView.swift
cat > "${PROJECT_ROOT}/BalconyiOS/Sources/Views/Discovery/QRScannerView.swift" << 'EOF'
import SwiftUI
import AVFoundation

/// Camera-based QR code scanner for device pairing.
struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    var onScanned: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack {
                // TODO: Implement AVCaptureSession-based QR scanner
                Text("Point camera at QR code\ndisplayed on your Mac")
                    .multilineTextAlignment(.center)
                    .font(.headline)
                    .padding()

                RoundedRectangle(cornerRadius: 12)
                    .stroke(.blue, lineWidth: 2)
                    .frame(width: 250, height: 250)
                    .overlay {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                    }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
EOF
detail "Created Views/Discovery/QRScannerView.swift"

# Views/Sessions/SessionListView.swift
cat > "${PROJECT_ROOT}/BalconyiOS/Sources/Views/Sessions/SessionListView.swift" << 'EOF'
import SwiftUI
import BalconyShared

struct SessionListView: View {
    @EnvironmentObject var sessionManager: SessionManager

    var body: some View {
        List {
            if sessionManager.sessions.isEmpty {
                ContentUnavailableView(
                    "No Active Sessions",
                    systemImage: "terminal",
                    description: Text("Start a Claude Code session on your Mac to see it here.")
                )
            } else {
                ForEach(sessionManager.sessions) { session in
                    NavigationLink(value: session) {
                        SessionRowView(session: session)
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .navigationDestination(for: Session.self) { session in
            TerminalContainerView(session: session)
        }
        .refreshable {
            await sessionManager.refreshSessions()
        }
    }
}
EOF
detail "Created Views/Sessions/SessionListView.swift"

# Views/Sessions/SessionRowView.swift
cat > "${PROJECT_ROOT}/BalconyiOS/Sources/Views/Sessions/SessionRowView.swift" << 'EOF'
import SwiftUI
import BalconyShared

struct SessionRowView: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.projectName)
                    .font(.headline)
                Spacer()
                StatusBadge(status: session.status)
            }

            HStack {
                Text("\(session.messageCount) messages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(session.lastActivityAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
EOF
detail "Created Views/Sessions/SessionRowView.swift"

# Views/Terminal/TerminalContainerView.swift
cat > "${PROJECT_ROOT}/BalconyiOS/Sources/Views/Terminal/TerminalContainerView.swift" << 'EOF'
import SwiftUI
import BalconyShared

struct TerminalContainerView: View {
    let session: Session
    @EnvironmentObject var sessionManager: SessionManager
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Terminal output area
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    // TODO: Replace with SwiftTerm TerminalView via UIViewRepresentable
                    Text("Terminal output for session: \(session.id)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.green)
                        .padding()
                }
            }
            .background(.black)

            Divider()

            // Input composer
            InputComposerView(text: $inputText) {
                Task {
                    await sessionManager.sendInput(inputText, to: session)
                    inputText = ""
                }
            }
        }
        .navigationTitle(session.projectName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await sessionManager.subscribe(to: session)
            }
        }
        .onDisappear {
            Task {
                await sessionManager.unsubscribe(from: session)
            }
        }
    }
}
EOF
detail "Created Views/Terminal/TerminalContainerView.swift"

# Views/Terminal/InputComposerView.swift
cat > "${PROJECT_ROOT}/BalconyiOS/Sources/Views/Terminal/InputComposerView.swift" << 'EOF'
import SwiftUI

struct InputComposerView: View {
    @Binding var text: String
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Quick actions
            HStack(spacing: 4) {
                QuickActionButton(title: "Approve", color: .green) { onSend() }
                QuickActionButton(title: "Deny", color: .red) { onSend() }
            }

            // Text input
            TextField("Send input...", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onSend() }

            // Send button
            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(text.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct QuickActionButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.caption)
            .buttonStyle(.bordered)
            .tint(color)
    }
}
EOF
detail "Created Views/Terminal/InputComposerView.swift"

# Views/Settings/SettingsView.swift
cat > "${PROJECT_ROOT}/BalconyiOS/Sources/Views/Settings/SettingsView.swift" << 'EOF'
import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Connected Macs") {
                    NavigationLink("Manage Devices") {
                        DeviceManagementView()
                    }
                }

                Section("Notifications") {
                    Toggle("Session Events", isOn: .constant(true))
                    Toggle("Tool Approvals", isOn: .constant(true))
                    Toggle("Session Complete", isOn: .constant(true))
                }

                Section("Security") {
                    Button("Reset Encryption Keys") {
                        // TODO: Reset and re-pair
                    }
                    .foregroundStyle(.red)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("0.1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
EOF
detail "Created Views/Settings/SettingsView.swift"

# Views/Settings/DeviceManagementView.swift
cat > "${PROJECT_ROOT}/BalconyiOS/Sources/Views/Settings/DeviceManagementView.swift" << 'EOF'
import SwiftUI
import BalconyShared

struct DeviceManagementView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        List {
            if connectionManager.pairedDevices.isEmpty {
                ContentUnavailableView(
                    "No Paired Devices",
                    systemImage: "desktopcomputer",
                    description: Text("Scan a QR code on your Mac to pair.")
                )
            } else {
                ForEach(connectionManager.pairedDevices, id: \.id) { device in
                    HStack {
                        Image(systemName: "desktopcomputer")
                        VStack(alignment: .leading) {
                            Text(device.name)
                                .font(.headline)
                            Text("Fingerprint: \(device.publicKeyFingerprint.prefix(8))...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { _ in
                    // TODO: Unpair device
                }
            }
        }
        .navigationTitle("Devices")
    }
}
EOF
detail "Created Views/Settings/DeviceManagementView.swift"

# Views/Components/ToolUseCard.swift
cat > "${PROJECT_ROOT}/BalconyiOS/Sources/Views/Components/ToolUseCard.swift" << 'EOF'
import SwiftUI
import BalconyShared

struct ToolUseCard: View {
    let toolUse: ToolUse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(statusColor)
                Text(toolUse.toolName)
                    .font(.headline)
                Spacer()
                Text(toolUse.status.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.1))
                    .clipShape(Capsule())
            }

            if !toolUse.input.isEmpty {
                Text(toolUse.input)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(3)
                    .foregroundStyle(.secondary)
            }

            if let output = toolUse.output {
                Text(output)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch toolUse.status {
        case .pending: return "clock"
        case .running: return "gear"
        case .completed: return "checkmark.circle"
        case .failed: return "xmark.circle"
        case .denied: return "nosign"
        }
    }

    private var statusColor: Color {
        switch toolUse.status {
        case .pending: return .yellow
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .denied: return .orange
        }
    }
}
EOF
detail "Created Views/Components/ToolUseCard.swift"

# Views/Components/StatusBadge.swift
cat > "${PROJECT_ROOT}/BalconyiOS/Sources/Views/Components/StatusBadge.swift" << 'EOF'
import SwiftUI
import BalconyShared

struct StatusBadge: View {
    let status: SessionStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        switch status {
        case .active: return .green
        case .idle: return .yellow
        case .waitingForInput: return .orange
        case .completed: return .gray
        case .error: return .red
        }
    }

    private var label: String {
        switch status {
        case .active: return "Active"
        case .idle: return "Idle"
        case .waitingForInput: return "Waiting"
        case .completed: return "Done"
        case .error: return "Error"
        }
    }
}
EOF
detail "Created Views/Components/StatusBadge.swift"

# Connection/BonjourBrowser.swift
cat > "${PROJECT_ROOT}/BalconyiOS/Sources/Connection/BonjourBrowser.swift" << 'EOF'
import Foundation
import Network
import BalconyShared
import os

/// Discovers BalconyMac instances on the local network via Bonjour.
actor BonjourBrowser {
    private let logger = Logger(subsystem: "com.balcony.ios", category: "BonjourBrowser")
    private var browser: NWBrowser?

    /// Discovered devices callback.
    var onDeviceFound: ((DeviceInfo) -> Void)?
    var onDeviceLost: ((String) -> Void)?

    /// Start browsing for Balcony services.
    func startBrowsing() {
        let params = NWParameters()
        params.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: "_balcony._tcp.", domain: nil), using: params)

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { [weak self] in
                await self?.handleResults(results, changes: changes)
            }
        }

        browser.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleState(state)
            }
        }

        browser.start(queue: .global())
        self.browser = browser
        logger.info("Started Bonjour browsing for _balcony._tcp.")
    }

    /// Stop browsing.
    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        logger.info("Stopped Bonjour browsing")
    }

    private func handleResults(_ results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                logger.info("Discovered: \(String(describing: result.endpoint))")
                // TODO: Extract device info from endpoint and TXT record
            case .removed(let result):
                logger.info("Lost: \(String(describing: result.endpoint))")
            default:
                break
            }
        }
    }

    private func handleState(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            logger.info("Browser ready")
        case .failed(let error):
            logger.error("Browser failed: \(error.localizedDescription)")
        default:
            break
        }
    }
}
EOF
detail "Created Connection/BonjourBrowser.swift"

# Connection/WebSocketClient.swift
cat > "${PROJECT_ROOT}/BalconyiOS/Sources/Connection/WebSocketClient.swift" << 'EOF'
import Foundation
import BalconyShared
import os

/// WebSocket client for connecting to BalconyMac.
actor WebSocketClient {
    private let logger = Logger(subsystem: "com.balcony.ios", category: "WebSocketClient")
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var isConnected = false

    /// Message receive callback.
    var onMessage: ((BalconyMessage) -> Void)?

    /// Connect to a BalconyMac WebSocket server.
    func connect(host: String, port: Int) async throws {
        let url = URL(string: "wss://\(host):\(port)/ws")!
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)

        // Trust self-signed certificates for local connections
        task.resume()

        self.session = session
        self.webSocketTask = task
        self.isConnected = true

        logger.info("Connected to \(host):\(port)")

        // Start receive loop
        Task {
            await receiveLoop()
        }
    }

    /// Disconnect from the server.
    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session = nil
        isConnected = false
        logger.info("Disconnected")
    }

    /// Send a message to the server.
    func send(_ message: BalconyMessage) async throws {
        let encoder = MessageEncoder()
        let data = try encoder.encode(message)
        try await webSocketTask?.send(.data(data))
    }

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }

        do {
            while isConnected {
                let message = try await task.receive()
                switch message {
                case .data(let data):
                    let decoder = MessageDecoder()
                    if let decoded = try? decoder.decode(data) {
                        onMessage?(decoded)
                    }
                case .string(let string):
                    let decoder = MessageDecoder()
                    if let decoded = try? decoder.decode(string) {
                        onMessage?(decoded)
                    }
                @unknown default:
                    break
                }
            }
        } catch {
            logger.error("Receive error: \(error.localizedDescription)")
            isConnected = false
            // TODO: Trigger reconnection with exponential backoff
        }
    }
}
EOF
detail "Created Connection/WebSocketClient.swift"

# Connection/BLECentral.swift
cat > "${PROJECT_ROOT}/BalconyiOS/Sources/Connection/BLECentral.swift" << 'EOF'
import Foundation
import CoreBluetooth
import os

/// BLE Central for proximity detection of Mac.
final class BLECentral: NSObject, ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.ios", category: "BLECentral")
    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?

    @Published var rssi: Int?
    @Published var isScanning = false

    /// Balcony BLE service UUID (must match BalconyMac).
    static let serviceUUID = CBUUID(string: "B41C0000-0001-0001-0001-000000000001")

    override init() {
        super.init()
    }

    /// Start scanning for Balcony peripherals.
    func startScanning() {
        centralManager = CBCentralManager(delegate: self, queue: .global())
    }

    /// Stop scanning.
    func stopScanning() {
        centralManager?.stopScan()
        centralManager = nil
        isScanning = false
    }
}

// MARK: - CBCentralManagerDelegate

extension BLECentral: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            logger.info("BLE powered on - starting scan")
            central.scanForPeripherals(
                withServices: [Self.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
            isScanning = true
        case .poweredOff:
            logger.warning("BLE powered off")
            isScanning = false
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        DispatchQueue.main.async {
            self.rssi = RSSI.intValue
        }
        logger.debug("Discovered peripheral RSSI: \(RSSI.intValue)")
    }
}
EOF
detail "Created Connection/BLECentral.swift"

# Connection/ConnectionManager.swift (iOS)
cat > "${PROJECT_ROOT}/BalconyiOS/Sources/Connection/ConnectionManager.swift" << 'EOF'
import Foundation
import BalconyShared
import os

/// Manages discovery, connection, and communication with BalconyMac.
@MainActor
final class ConnectionManager: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.ios", category: "ConnectionManager")

    @Published var discoveredDevices: [DeviceInfo] = []
    @Published var pairedDevices: [DeviceInfo] = []
    @Published var isConnected = false
    @Published var connectedDevice: DeviceInfo?

    private let bonjourBrowser = BonjourBrowser()
    private let webSocketClient = WebSocketClient()
    private let bleCentral = BLECentral()
    private let cryptoManager = CryptoManager()

    /// Start discovering nearby Macs.
    func startDiscovery() {
        Task {
            await bonjourBrowser.startBrowsing()
        }
        bleCentral.startScanning()
        logger.info("Discovery started")
    }

    /// Stop discovery.
    func stopDiscovery() {
        Task {
            await bonjourBrowser.stopBrowsing()
        }
        bleCentral.stopScanning()
        logger.info("Discovery stopped")
    }

    /// Connect to a discovered Mac.
    func connect(to device: DeviceInfo) async {
        logger.info("Connecting to \(device.name)")
        // TODO: Resolve Bonjour endpoint to host/port
        // TODO: Establish WebSocket connection
        // TODO: Perform encrypted handshake
        isConnected = true
        connectedDevice = device
    }

    /// Disconnect from current Mac.
    func disconnect() async {
        await webSocketClient.disconnect()
        isConnected = false
        connectedDevice = nil
        logger.info("Disconnected")
    }
}
EOF
detail "Created Connection/ConnectionManager.swift"

# Session/SessionManager.swift (iOS)
cat > "${PROJECT_ROOT}/BalconyiOS/Sources/Session/SessionManager.swift" << 'EOF'
import Foundation
import BalconyShared
import os

/// Manages Claude Code sessions received from the connected Mac.
@MainActor
final class SessionManager: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.ios", category: "SessionManager")

    @Published var sessions: [Session] = []
    @Published var activeSession: Session?

    /// Refresh the session list from the connected Mac.
    func refreshSessions() async {
        logger.info("Refreshing sessions")
        // TODO: Request session list from Mac via WebSocket
    }

    /// Subscribe to real-time updates for a session.
    func subscribe(to session: Session) async {
        logger.info("Subscribing to session: \(session.id)")
        activeSession = session
        // TODO: Send sessionSubscribe message
    }

    /// Unsubscribe from a session.
    func unsubscribe(from session: Session) async {
        logger.info("Unsubscribing from session: \(session.id)")
        if activeSession?.id == session.id {
            activeSession = nil
        }
        // TODO: Send sessionUnsubscribe message
    }

    /// Send user input to a session on the Mac.
    func sendInput(_ input: String, to session: Session) async {
        logger.info("Sending input to session: \(session.id)")
        // TODO: Send userInput message via WebSocket
    }
}
EOF
detail "Created Session/SessionManager.swift"

# Notifications/NotificationManager.swift
cat > "${PROJECT_ROOT}/BalconyiOS/Sources/Notifications/NotificationManager.swift" << 'EOF'
import Foundation
import UserNotifications
import os

/// Manages local and push notifications for session events.
final class NotificationManager: NSObject, ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.ios", category: "NotificationManager")

    override init() {
        super.init()
    }

    /// Request notification permissions.
    func requestPermissions() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("Notification permission: \(granted ? "granted" : "denied")")
            return granted
        } catch {
            logger.error("Failed to request notification permission: \(error.localizedDescription)")
            return false
        }
    }

    /// Schedule a local notification for a session event.
    func notifySessionEvent(sessionName: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Balcony - \(sessionName)"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.logger.error("Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }
}
EOF
detail "Created Notifications/NotificationManager.swift"

success "BalconyiOS source files created"

# -- BalconyiOS Resources -------------------------------------------------------
step "Creating BalconyiOS resources"

# Info.plist
cat > "${PROJECT_ROOT}/BalconyiOS/Resources/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Balcony</string>
    <key>CFBundleDisplayName</key>
    <string>Balcony</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>UILaunchScreen</key>
    <dict/>
    <key>NSCameraUsageDescription</key>
    <string>Balcony uses the camera to scan QR codes for device pairing.</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Balcony uses Bluetooth to detect proximity to your Mac.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Balcony uses the local network to connect to your Mac.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_balcony._tcp.</string>
    </array>
    <key>UIBackgroundModes</key>
    <array>
        <string>bluetooth-central</string>
        <string>remote-notification</string>
    </array>
</dict>
</plist>
EOF
detail "Created Info.plist"

# Entitlements
cat > "${PROJECT_ROOT}/BalconyiOS/Resources/BalconyiOS.entitlements" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.networking.wifi-info</key>
    <true/>
</dict>
</plist>
EOF
detail "Created BalconyiOS.entitlements"

# AppIcon Contents.json
cat > "${PROJECT_ROOT}/BalconyiOS/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json" << 'EOF'
{
  "images" : [
    {
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

# Assets.xcassets Contents.json
cat > "${PROJECT_ROOT}/BalconyiOS/Resources/Assets.xcassets/Contents.json" << 'EOF'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
detail "Created Assets.xcassets"

success "BalconyiOS resources created"

# -- Supabase Scaffold ---------------------------------------------------------
step "Creating Supabase scaffold (Phase 2)"

cat > "${PROJECT_ROOT}/supabase/config.toml" << 'EOF'
# Supabase configuration for Balcony cloud relay (Phase 2)
[project]
name = "balcony"

[db]
port = 54322
EOF
detail "Created config.toml"

cat > "${PROJECT_ROOT}/supabase/migrations/001_initial_schema.sql" << 'EOF'
-- Balcony Cloud Relay Schema (Phase 2)
-- This migration creates the initial tables for device pairing and message relay.

-- Devices table
CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    platform TEXT NOT NULL CHECK (platform IN ('macOS', 'iOS')),
    public_key TEXT NOT NULL,
    fcm_token TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Pairings table
CREATE TABLE pairings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mac_device_id UUID REFERENCES devices(id) ON DELETE CASCADE,
    ios_device_id UUID REFERENCES devices(id) ON DELETE CASCADE,
    shared_secret_hash TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(mac_device_id, ios_device_id)
);

-- Relay messages table (ephemeral, for store-and-forward)
CREATE TABLE relay_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pairing_id UUID REFERENCES pairings(id) ON DELETE CASCADE,
    direction TEXT NOT NULL CHECK (direction IN ('mac_to_ios', 'ios_to_mac')),
    encrypted_payload BYTEA NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '1 hour'),
    delivered BOOLEAN DEFAULT FALSE
);

-- Row-Level Security
ALTER TABLE devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE pairings ENABLE ROW LEVEL SECURITY;
ALTER TABLE relay_messages ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can manage their own devices"
    ON devices FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users can see their pairings"
    ON pairings FOR ALL
    USING (
        mac_device_id IN (SELECT id FROM devices WHERE user_id = auth.uid())
        OR ios_device_id IN (SELECT id FROM devices WHERE user_id = auth.uid())
    );

-- Indexes
CREATE INDEX idx_relay_messages_pairing ON relay_messages(pairing_id, delivered);
CREATE INDEX idx_relay_messages_expires ON relay_messages(expires_at) WHERE NOT delivered;
EOF
detail "Created 001_initial_schema.sql"

cat > "${PROJECT_ROOT}/supabase/functions/relay-message/index.ts" << 'EOF'
// Balcony Cloud Relay - Message Relay Function (Phase 2)
// Stores encrypted messages for forwarding between paired devices.

import { serve } from "https://deno.land/std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js";

serve(async (req: Request) => {
    // TODO: Implement message relay
    // 1. Authenticate request
    // 2. Validate pairing exists
    // 3. Store encrypted message
    // 4. Notify recipient via Realtime channel
    return new Response(JSON.stringify({ status: "not_implemented" }), {
        headers: { "Content-Type": "application/json" },
        status: 501,
    });
});
EOF
detail "Created relay-message function"

cat > "${PROJECT_ROOT}/supabase/functions/send-push/index.ts" << 'EOF'
// Balcony Cloud Relay - Push Notification Function (Phase 2)
// Dispatches FCM push notifications when user is away.

import { serve } from "https://deno.land/std/http/server.ts";

serve(async (req: Request) => {
    // TODO: Implement push notification dispatch
    // 1. Authenticate request
    // 2. Look up device FCM token
    // 3. Send notification via FCM HTTP v1 API
    return new Response(JSON.stringify({ status: "not_implemented" }), {
        headers: { "Content-Type": "application/json" },
        status: 501,
    });
});
EOF
detail "Created send-push function"

cat > "${PROJECT_ROOT}/supabase/functions/cleanup/index.ts" << 'EOF'
// Balcony Cloud Relay - Cleanup Function (Phase 2)
// Deletes expired relay messages. Intended to run on a cron schedule.

import { serve } from "https://deno.land/std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js";

serve(async (req: Request) => {
    // TODO: Implement cleanup
    // 1. Delete relay_messages where expires_at < NOW()
    // 2. Return count of deleted messages
    return new Response(JSON.stringify({ status: "not_implemented" }), {
        headers: { "Content-Type": "application/json" },
        status: 501,
    });
});
EOF
detail "Created cleanup function"

success "Supabase scaffold created"

# -- xcodegen project.yml ------------------------------------------------------
step "Creating xcodegen project.yml"

cat > "${PROJECT_ROOT}/project.yml" << 'EOF'
name: Balcony
options:
  bundleIdPrefix: com.balcony
  deploymentTarget:
    macOS: "14.0"
    iOS: "16.0"
  xcodeVersion: "15.0"
  createIntermediateGroups: true
  generateEmptyDirectories: true
  groupSortPosition: top

packages:
  BalconyShared:
    path: BalconyShared

settings:
  base:
    SWIFT_VERSION: "5.9"

targets:
  BalconyMac:
    type: application
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: BalconyMac/Sources
    resources:
      - path: BalconyMac/Resources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.balcony.mac
        INFOPLIST_FILE: BalconyMac/Resources/Info.plist
        CODE_SIGN_ENTITLEMENTS: BalconyMac/Resources/BalconyMac.entitlements
        PRODUCT_NAME: Balcony
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        LD_RUNPATH_SEARCH_PATHS:
          - $(inherited)
          - "@executable_path/../Frameworks"
    dependencies:
      - package: BalconyShared

  BalconyiOS:
    type: application
    platform: iOS
    deploymentTarget: "16.0"
    sources:
      - path: BalconyiOS/Sources
    resources:
      - path: BalconyiOS/Resources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.balcony.ios
        INFOPLIST_FILE: BalconyiOS/Resources/Info.plist
        CODE_SIGN_ENTITLEMENTS: BalconyiOS/Resources/BalconyiOS.entitlements
        PRODUCT_NAME: Balcony
        IPHONEOS_DEPLOYMENT_TARGET: "16.0"
        TARGETED_DEVICE_FAMILY: 1
        LD_RUNPATH_SEARCH_PATHS:
          - $(inherited)
          - "@executable_path/Frameworks"
    dependencies:
      - package: BalconyShared
      - sdk: AVFoundation.framework
      - sdk: CoreBluetooth.framework

  BalconySharedTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: BalconyShared/Tests/BalconySharedTests
    dependencies:
      - package: BalconyShared
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.balcony.shared.tests
EOF
success "Created project.yml"

# -- Generate Xcode Project with xcodegen --------------------------------------
step "Generating Xcode project with xcodegen"

cd "${PROJECT_ROOT}"
xcodegen generate 2>&1 | while IFS= read -r line; do
    detail "$line"
done

if [ -d "${PROJECT_ROOT}/Balcony.xcodeproj" ]; then
    success "Xcode project generated: Balcony.xcodeproj"
else
    error "Failed to generate Xcode project"
    exit 1
fi

# -- CLAUDE.md -----------------------------------------------------------------
step "Creating CLAUDE.md"

cat > "${PROJECT_ROOT}/CLAUDE.md" << 'EOF'
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
EOF
success "Created CLAUDE.md"

# -- .gitignore ----------------------------------------------------------------
step "Creating .gitignore"

cat > "${PROJECT_ROOT}/.gitignore" << 'EOF'
# Xcode
*.xcodeproj/project.xcworkspace/
*.xcodeproj/xcuserdata/
*.xcworkspace/xcuserdata/
xcuserdata/
*.xccheckout
*.xcscmblueprint
DerivedData/
build/
*.moved-aside
*.pbxuser
!default.pbxuser
*.mode1v3
!default.mode1v3
*.mode2v3
!default.mode2v3
*.perspectivev3
!default.perspectivev3

# Swift Package Manager
.build/
.swiftpm/
Package.resolved
Packages/

# macOS
.DS_Store
.AppleDouble
.LSOverride
._*
.Spotlight-V100
.Trashes

# IDE
*.swp
*.swo
*~
.idea/
.vscode/

# Secrets & Keys
*.key
*.pem
*.p12
.env
.env.*

# Build artifacts
*.ipa
*.dSYM.zip
*.dSYM
*.app

# Claude temp files
.claude/temp/

# Supabase
supabase/.temp/
EOF
success "Created .gitignore"

# -- Initialize Git Repository -------------------------------------------------
step "Initializing git repository"

cd "${PROJECT_ROOT}"
if [ ! -d ".git" ]; then
    git init 2>&1 | while IFS= read -r line; do
        detail "$line"
    done
    git add -A 2>&1
    git commit -m "Initial scaffold: Balcony - Claude Code iOS Companion

- BalconyShared: Swift package with models, crypto, parser, protocol
- BalconyMac: macOS menu bar agent stubs (WebSocket, Bonjour, BLE, sessions)
- BalconyiOS: iOS app stubs (discovery, sessions, terminal, settings)
- Supabase: Phase 2 cloud relay scaffold
- xcodegen project.yml for Xcode project generation
- CLAUDE.md with project conventions" 2>&1 | while IFS= read -r line; do
        detail "$line"
    done
    success "Git repository initialized with initial commit"
else
    warn "Git repository already exists, skipping init"
fi

# -- Resolve Swift Packages ----------------------------------------------------
step "Resolving Swift Package dependencies"

cd "${PROJECT_ROOT}/BalconyShared"
swift package resolve 2>&1 | while IFS= read -r line; do
    detail "$line"
done
success "Swift packages resolved"

# -- Summary -------------------------------------------------------------------
echo ""
echo -e "${BOLD}${BALCONY}=============================================${NC}"
echo -e "${BOLD}${BALCONY}  Balcony Bootstrap Complete!${NC}"
echo -e "${BOLD}${BALCONY}=============================================${NC}"
echo ""
echo -e "${BOLD}Project Structure:${NC}"
echo -e "  ${DIM}BalconyShared/${NC}   Swift Package (models, crypto, parser)"
echo -e "  ${DIM}BalconyMac/${NC}      macOS Menu Bar Agent"
echo -e "  ${DIM}BalconyiOS/${NC}      iOS Companion App"
echo -e "  ${DIM}supabase/${NC}        Cloud Relay (Phase 2 scaffold)"
echo ""
echo -e "${BOLD}Generated Files:${NC}"

# Count files
total_swift=$(find "${PROJECT_ROOT}" -name "*.swift" -not -path "*/.build/*" | wc -l | tr -d ' ' || echo "0")
total_files=$(find "${PROJECT_ROOT}" -type f -not -path "*/.git/*" -not -path "*/.build/*" | wc -l | tr -d ' ' || echo "0")

echo -e "  Swift files:    ${GREEN}${total_swift}${NC}"
echo -e "  Total files:    ${GREEN}${total_files}${NC}"
echo ""
echo -e "${BOLD}Next Steps:${NC}"
echo -e "  1. Open in Xcode:  ${CYAN}open Balcony.xcodeproj${NC}"
echo -e "  2. Run tests:      ${CYAN}cd BalconyShared && swift test${NC}"
echo -e "  3. Build Mac app:  ${CYAN}Cmd+B in Xcode (BalconyMac scheme)${NC}"
echo -e "  4. Build iOS app:  ${CYAN}Cmd+B in Xcode (BalconyiOS scheme)${NC}"
echo -e "  5. Read the plan:  ${CYAN}cat .claude/temp/PLAN_BALCONY.md${NC}"
echo ""
echo -e "${DIM}Happy building! 🏗️${NC}"
