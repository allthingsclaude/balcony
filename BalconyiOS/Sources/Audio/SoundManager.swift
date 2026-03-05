import AudioToolbox
import Foundation

// MARK: - NotificationSound

/// Available notification sounds for background session alerts.
enum NotificationSound: String, CaseIterable, Identifiable {
    case chime
    case bell
    case drop
    case pulse
    case anticipate
    case bloom
    case calypso
    case descent
    case fanfare
    case ladder
    case minuet
    case newsFlash
    case noir
    case sherwood
    case spell
    case suspense
    case telegraph
    case tiptoes
    case typewriters
    case update
    case none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chime: return "Chime"
        case .bell: return "Bell"
        case .drop: return "Drop"
        case .pulse: return "Pulse"
        case .anticipate: return "Anticipate"
        case .bloom: return "Bloom"
        case .calypso: return "Calypso"
        case .descent: return "Descent"
        case .fanfare: return "Fanfare"
        case .ladder: return "Ladder"
        case .minuet: return "Minuet"
        case .newsFlash: return "News Flash"
        case .noir: return "Noir"
        case .sherwood: return "Sherwood Forest"
        case .spell: return "Spell"
        case .suspense: return "Suspense"
        case .telegraph: return "Telegraph"
        case .tiptoes: return "Tiptoes"
        case .typewriters: return "Typewriters"
        case .update: return "Update"
        case .none: return "None"
        }
    }

    var systemSoundID: SystemSoundID? {
        switch self {
        case .chime: return 1025
        case .bell: return 1013
        case .drop: return 1104
        case .pulse: return 1052
        case .anticipate: return 1150
        case .bloom: return 1151
        case .calypso: return 1152
        case .descent: return 1154
        case .fanfare: return 1155
        case .ladder: return 1156
        case .minuet: return 1157
        case .newsFlash: return 1158
        case .noir: return 1159
        case .sherwood: return 1160
        case .spell: return 1161
        case .suspense: return 1162
        case .telegraph: return 1163
        case .tiptoes: return 1164
        case .typewriters: return 1165
        case .update: return 1166
        case .none: return nil
        }
    }
}

// MARK: - SoundManager

/// Plays notification sounds for background session events.
@MainActor
final class SoundManager {
    static let shared = SoundManager()

    /// UserDefaults key for the attention sound (AI needs user action).
    static let attentionSoundKey = "attentionSound"

    /// UserDefaults key for the done sound (AI finished, waiting for next prompt).
    static let doneSoundKey = "doneSound"

    private init() {}

    /// Play a specific notification sound.
    func play(_ sound: NotificationSound) {
        guard let id = sound.systemSoundID else { return }
        AudioServicesPlaySystemSound(id)
    }

    /// Play the user's preferred attention sound (AI needs action).
    func playAttentionSound() {
        let raw = UserDefaults.standard.string(forKey: Self.attentionSoundKey)
            ?? NotificationSound.noir.rawValue
        let sound = NotificationSound(rawValue: raw) ?? .noir
        play(sound)
    }

    /// Play the user's preferred done sound (AI finished).
    func playDoneSound() {
        let raw = UserDefaults.standard.string(forKey: Self.doneSoundKey)
            ?? NotificationSound.noir.rawValue
        let sound = NotificationSound(rawValue: raw) ?? .noir
        play(sound)
    }

    /// Migrate old single `notificationSound` key to the new dual-sound keys.
    static func migrateOldSoundPreference() {
        let ud = UserDefaults.standard
        if let oldSound = ud.string(forKey: "notificationSound"),
           ud.object(forKey: attentionSoundKey) == nil,
           ud.object(forKey: doneSoundKey) == nil {
            ud.set(oldSound, forKey: attentionSoundKey)
            ud.set(oldSound, forKey: doneSoundKey)
            ud.removeObject(forKey: "notificationSound")
        }
    }
}
