import AVFoundation
import Foundation
import UserNotifications

// MARK: - NotificationSound

/// Available notification sounds for session alerts.
/// Backed by bundled .caf files shared across iOS and macOS.
enum NotificationSound: String, CaseIterable, Identifiable {
    case aurora
    case beacon
    case breeze
    case dew
    case drift
    case droplet
    case echo
    case ember
    case glint
    case prism
    case pulse
    case ripple
    case signal
    case spark
    case whisper
    case none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aurora: return "Aurora"
        case .beacon: return "Beacon"
        case .breeze: return "Breeze"
        case .dew: return "Dew"
        case .drift: return "Drift"
        case .droplet: return "Droplet"
        case .echo: return "Echo"
        case .ember: return "Ember"
        case .glint: return "Glint"
        case .prism: return "Prism"
        case .pulse: return "Pulse"
        case .ripple: return "Ripple"
        case .signal: return "Signal"
        case .spark: return "Spark"
        case .whisper: return "Whisper"
        case .none: return "None"
        }
    }

    /// Bundled .caf filename.
    var cafFileName: String? {
        switch self {
        case .aurora: return "Aurora.caf"
        case .beacon: return "Beacon.caf"
        case .breeze: return "Breeze.caf"
        case .dew: return "Dew.caf"
        case .drift: return "Drift.caf"
        case .droplet: return "Droplet.caf"
        case .echo: return "Echo.caf"
        case .ember: return "Ember.caf"
        case .glint: return "Glint.caf"
        case .prism: return "Prism.caf"
        case .pulse: return "Pulse.caf"
        case .ripple: return "Ripple.caf"
        case .signal: return "Signal.caf"
        case .spark: return "Spark.caf"
        case .whisper: return "Whisper.caf"
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
            ?? NotificationSound.signal.rawValue
        return NotificationSound(rawValue: raw) ?? .signal
    }

    /// The user's preferred done sound (AI finished).
    var doneSound: NotificationSound {
        let raw = UserDefaults.standard.string(forKey: Self.doneSoundKey)
            ?? NotificationSound.breeze.rawValue
        return NotificationSound(rawValue: raw) ?? .breeze
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
