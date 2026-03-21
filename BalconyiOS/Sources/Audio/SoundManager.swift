import AVFoundation
import Foundation
import UserNotifications

// MARK: - NotificationSound

/// Available notification sounds for session alerts.
/// Backed by bundled .caf files shared across iOS and macOS.
enum NotificationSound: String, CaseIterable, Identifiable {
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

    /// Bundled .caf filename.
    var cafFileName: String? {
        switch self {
        case .anticipate: return "Anticipate.caf"
        case .bloom: return "Bloom.caf"
        case .calypso: return "Calypso.caf"
        case .descent: return "Descent.caf"
        case .fanfare: return "Fanfare.caf"
        case .ladder: return "Ladder.caf"
        case .minuet: return "Minuet.caf"
        case .newsFlash: return "News_Flash.caf"
        case .noir: return "Noir.caf"
        case .sherwood: return "Sherwood_Forest.caf"
        case .spell: return "Spell.caf"
        case .suspense: return "Suspense.caf"
        case .telegraph: return "Telegraph.caf"
        case .tiptoes: return "Tiptoes.caf"
        case .typewriters: return "Typewriters.caf"
        case .update: return "Update.caf"
        case .none: return nil
        }
    }

    /// UNNotificationSound matching this sound, or .default if none.
    var notificationSound: UNNotificationSound {
        if let fileName = cafFileName {
            return UNNotificationSound(named: UNNotificationSoundName(rawValue: fileName))
        }
        return .default
    }
}

// MARK: - SoundManager

/// Plays notification sounds for background session events using AVAudioPlayer
/// for consistent playback across platforms.
@MainActor
final class SoundManager {
    static let shared = SoundManager()

    /// UserDefaults key for the attention sound (AI needs user action).
    static let attentionSoundKey = "attentionSound"

    /// UserDefaults key for the done sound (AI finished, waiting for next prompt).
    static let doneSoundKey = "doneSound"

    /// Retained player for current playback.
    private var player: AVAudioPlayer?

    private init() {}

    /// Play a specific notification sound from the bundled .caf file.
    func play(_ sound: NotificationSound) {
        guard let fileName = sound.cafFileName,
              let url = Bundle.main.url(forResource: fileName.replacingOccurrences(of: ".caf", with: ""),
                                        withExtension: "caf") else { return }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            // Silently fail — sound is non-critical
        }
    }

    /// The user's preferred attention sound (AI needs action).
    var attentionSound: NotificationSound {
        let raw = UserDefaults.standard.string(forKey: Self.attentionSoundKey)
            ?? NotificationSound.noir.rawValue
        return NotificationSound(rawValue: raw) ?? .noir
    }

    /// The user's preferred done sound (AI finished).
    var doneSound: NotificationSound {
        let raw = UserDefaults.standard.string(forKey: Self.doneSoundKey)
            ?? NotificationSound.noir.rawValue
        return NotificationSound(rawValue: raw) ?? .noir
    }

    /// Play the user's preferred attention sound (AI needs action).
    func playAttentionSound() {
        play(attentionSound)
    }

    /// Play the user's preferred done sound (AI finished).
    func playDoneSound() {
        play(doneSound)
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
