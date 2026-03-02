import AudioToolbox
import Foundation

// MARK: - NotificationSound

/// Available notification sounds for background session alerts.
enum NotificationSound: String, CaseIterable, Identifiable {
    case chime
    case bell
    case drop
    case pulse
    case none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chime: return "Chime"
        case .bell: return "Bell"
        case .drop: return "Drop"
        case .pulse: return "Pulse"
        case .none: return "None"
        }
    }

    var systemSoundID: SystemSoundID? {
        switch self {
        case .chime: return 1025
        case .bell: return 1013
        case .drop: return 1104
        case .pulse: return 1052
        case .none: return nil
        }
    }
}

// MARK: - SoundManager

/// Plays notification sounds for background session events.
@MainActor
final class SoundManager {
    static let shared = SoundManager()

    private init() {}

    /// Play a specific notification sound.
    func play(_ sound: NotificationSound) {
        guard let id = sound.systemSoundID else { return }
        AudioServicesPlaySystemSound(id)
    }

    /// Play the user's preferred notification sound from UserDefaults.
    func playNotification() {
        let raw = UserDefaults.standard.string(forKey: "notificationSound") ?? NotificationSound.chime.rawValue
        let sound = NotificationSound(rawValue: raw) ?? .chime
        play(sound)
    }
}
