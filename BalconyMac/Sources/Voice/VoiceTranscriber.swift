import Foundation
import Speech
import os

/// Handles microphone capture and live speech-to-text using Apple's Speech framework.
/// Uses on-device recognition when available (macOS 14+) for privacy and low latency.
@MainActor
@Observable
final class VoiceTranscriber {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "VoiceTranscriber")

    /// Whether audio is currently being recorded and transcribed.
    private(set) var isRecording = false

    /// The latest (partial or final) transcription result.
    private(set) var transcript = ""

    /// Current authorization status for speech recognition.
    private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    /// Whether voice input is available (authorized and a recognizer exists for the selected locale).
    var isAvailable: Bool {
        currentRecognizer?.isAvailable == true && authorizationStatus == .authorized
    }

    /// The recognizer for the currently selected locale.
    private var currentRecognizer: SFSpeechRecognizer? {
        let localeId = PreferencesManager.shared.voiceLanguage
        if localeId.isEmpty {
            return SFSpeechRecognizer()  // system default
        }
        return SFSpeechRecognizer(locale: Locale(identifier: localeId))
    }

    /// All supported locale identifiers, sorted by display name.
    static let supportedLanguages: [(id: String, name: String)] = {
        let locales = SFSpeechRecognizer.supportedLocales()
        return locales.map { locale in
            let id = locale.identifier
            let name = Locale.current.localizedString(forIdentifier: id) ?? id
            return (id: id, name: name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    // MARK: - Authorization

    /// Request speech recognition permission. Call this when the user enables voice input.
    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.authorizationStatus = status
                self?.logger.info("Speech recognition authorization: \(status.rawValue)")
            }
        }
    }

    /// Check current authorization without prompting.
    func checkAuthorization() {
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }

    // MARK: - Recording

    /// Start recording audio and transcribing speech.
    func startRecording() {
        guard !isRecording else { return }
        guard let recognizer = currentRecognizer, recognizer.isAvailable else {
            logger.error("Speech recognizer not available")
            return
        }

        transcript = ""

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        // Prefer on-device but don't require it — many languages
        // only work via server-side recognition
        request.requiresOnDeviceRecognition = false

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if let error, self.isRecording {
                    self.logger.error("Recognition error: \(error.localizedDescription)")
                }
            }
        }

        do {
            engine.prepare()
            try engine.start()
            self.audioEngine = engine
            self.recognitionRequest = request
            isRecording = true
            logger.info("Voice recording started")
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
            recognitionTask?.cancel()
            recognitionTask = nil
        }
    }

    /// Stop recording and return the final transcript.
    @discardableResult
    func stopRecording() -> String {
        guard isRecording else { return transcript }

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false

        let result = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("Voice recording stopped, transcript: '\(result.prefix(80))'")
        return result
    }
}
