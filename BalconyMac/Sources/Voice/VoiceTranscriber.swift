import Foundation
import Speech
import os

/// Handles microphone capture and live speech-to-text using Apple's Speech framework.
/// Supports dual-language recognition by running two recognizers in parallel on the
/// same audio stream and picking the higher-confidence result.
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

    // Primary language
    private var primaryRequest: SFSpeechAudioBufferRecognitionRequest?
    private var primaryTask: SFSpeechRecognitionTask?
    private var primaryTranscript = ""
    private var primaryConfidence: Float = 0

    // Secondary language (optional)
    private var secondaryRequest: SFSpeechAudioBufferRecognitionRequest?
    private var secondaryTask: SFSpeechRecognitionTask?
    private var secondaryTranscript = ""
    private var secondaryConfidence: Float = 0

    /// Whether voice input is available (authorized and a recognizer exists for the selected locale).
    var isAvailable: Bool {
        makeRecognizer(for: PreferencesManager.shared.voiceLanguage)?.isAvailable == true
            && authorizationStatus == .authorized
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
    /// Runs two recognizers in parallel if a secondary language is configured.
    func startRecording() {
        guard !isRecording else { return }

        let primaryLocale = PreferencesManager.shared.voiceLanguage
        let secondaryLocale = PreferencesManager.shared.voiceSecondaryLanguage

        guard let primaryRecognizer = makeRecognizer(for: primaryLocale),
              primaryRecognizer.isAvailable else {
            logger.error("Primary speech recognizer not available")
            return
        }

        let hasSecondary = !secondaryLocale.isEmpty && secondaryLocale != primaryLocale
        let secondaryRecognizer = hasSecondary ? makeRecognizer(for: secondaryLocale) : nil

        transcript = ""
        primaryTranscript = ""
        primaryConfidence = 0
        secondaryTranscript = ""
        secondaryConfidence = 0

        let engine = AVAudioEngine()

        // Set up primary recognition
        let pRequest = makeRequest()
        primaryTask = primaryRecognizer.recognitionTask(with: pRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                if let result {
                    self.primaryTranscript = result.bestTranscription.formattedString
                    self.primaryConfidence = self.averageConfidence(result.bestTranscription)
                    self.pickBestTranscript()
                }
                if let error {
                    self.logger.debug("Primary recognition error: \(error.localizedDescription)")
                }
            }
        }
        primaryRequest = pRequest

        // Set up secondary recognition (if configured)
        if let secRecognizer = secondaryRecognizer, secRecognizer.isAvailable {
            let sRequest = makeRequest()
            secondaryTask = secRecognizer.recognitionTask(with: sRequest) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.isRecording else { return }
                    if let result {
                        self.secondaryTranscript = result.bestTranscription.formattedString
                        self.secondaryConfidence = self.averageConfidence(result.bestTranscription)
                        self.pickBestTranscript()
                    }
                    if let error {
                        self.logger.debug("Secondary recognition error: \(error.localizedDescription)")
                    }
                }
            }
            secondaryRequest = sRequest
            logger.info("Dual-language recognition: primary=\(primaryLocale.isEmpty ? "system" : primaryLocale) secondary=\(secondaryLocale)")
        }

        // Tap audio and feed both requests
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.primaryRequest?.append(buffer)
            self.secondaryRequest?.append(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
            self.audioEngine = engine
            isRecording = true
            logger.info("Voice recording started")
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
            primaryTask?.cancel()
            secondaryTask?.cancel()
            primaryTask = nil
            secondaryTask = nil
        }
    }

    /// Stop recording and return the final transcript.
    @discardableResult
    func stopRecording() -> String {
        guard isRecording else { return transcript }

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)

        primaryRequest?.endAudio()
        secondaryRequest?.endAudio()
        primaryTask?.cancel()
        secondaryTask?.cancel()

        audioEngine = nil
        primaryRequest = nil
        secondaryRequest = nil
        primaryTask = nil
        secondaryTask = nil
        isRecording = false

        let result = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("Voice recording stopped, transcript: '\(result.prefix(80))'")
        return result
    }

    // MARK: - Private

    private func makeRecognizer(for localeId: String) -> SFSpeechRecognizer? {
        if localeId.isEmpty {
            return SFSpeechRecognizer()
        }
        return SFSpeechRecognizer(locale: Locale(identifier: localeId))
    }

    private func makeRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = false
        return request
    }

    /// Pick the transcript with higher average confidence.
    private func pickBestTranscript() {
        if secondaryRequest == nil {
            // Single language mode
            transcript = primaryTranscript
            return
        }

        // Both languages active — pick higher confidence, fall back to longer text
        if primaryConfidence > 0 || secondaryConfidence > 0 {
            if secondaryConfidence > primaryConfidence && !secondaryTranscript.isEmpty {
                transcript = secondaryTranscript
            } else {
                transcript = primaryTranscript
            }
        } else if !primaryTranscript.isEmpty {
            transcript = primaryTranscript
        } else {
            transcript = secondaryTranscript
        }
    }

    /// Average confidence across all segments of a transcription.
    private func averageConfidence(_ transcription: SFTranscription) -> Float {
        let segments = transcription.segments
        guard !segments.isEmpty else { return 0 }
        let total = segments.reduce(Float(0)) { $0 + $1.confidence }
        return total / Float(segments.count)
    }
}
