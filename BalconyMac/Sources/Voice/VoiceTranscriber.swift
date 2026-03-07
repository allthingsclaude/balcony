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

    // Cached recognizers — recreated only when locale changes
    private var cachedPrimaryRecognizer: SFSpeechRecognizer?
    private var cachedPrimaryLocale = ""
    private var cachedSecondaryRecognizer: SFSpeechRecognizer?
    private var cachedSecondaryLocale = ""

    /// Whether voice input is available (authorized and a recognizer exists for the selected locale).
    var isAvailable: Bool {
        recognizer(for: PreferencesManager.shared.voiceLanguage)?.isAvailable == true
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

        guard let primaryRecognizer = recognizer(for: primaryLocale),
              primaryRecognizer.isAvailable else {
            logger.error("Primary speech recognizer not available")
            return
        }

        let hasSecondary = !secondaryLocale.isEmpty && secondaryLocale != primaryLocale
        let secondaryRecognizer = hasSecondary ? recognizer(for: secondaryLocale) : nil

        transcript = ""
        frozenPrefix = ""
        primaryTranscript = ""
        primaryConfidence = 0
        secondaryTranscript = ""
        secondaryConfidence = 0
        currentWinner = .primary
        committed = false

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

    /// Remove the last word from the current transcript.
    /// Freezes the edited text and restarts recognition so deleted words don't return.
    func deleteLastWord() {
        guard !transcript.isEmpty else { return }
        var words = transcript.split(separator: " ", omittingEmptySubsequences: true)
        guard !words.isEmpty else { transcript = ""; return }
        words.removeLast()
        let edited = words.joined(separator: " ")
        frozenPrefix = edited
        transcript = edited
        restartRecognitionTasks()
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

    /// Return a cached recognizer for the locale, recreating only when the locale changes.
    private func recognizer(for localeId: String) -> SFSpeechRecognizer? {
        // Check primary cache
        if cachedPrimaryLocale == localeId, let r = cachedPrimaryRecognizer { return r }
        // Check secondary cache
        if cachedSecondaryLocale == localeId, let r = cachedSecondaryRecognizer { return r }

        // Create and cache
        let r = localeId.isEmpty
            ? SFSpeechRecognizer()
            : SFSpeechRecognizer(locale: Locale(identifier: localeId))

        // Store in the first available slot, or overwrite primary
        if cachedPrimaryRecognizer == nil || cachedPrimaryLocale == localeId {
            cachedPrimaryRecognizer = r
            cachedPrimaryLocale = localeId
        } else {
            cachedSecondaryRecognizer = r
            cachedSecondaryLocale = localeId
        }
        return r
    }

    private func makeRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = false
        return request
    }

    /// Which recognizer is currently winning.
    private enum Winner { case primary, secondary }
    private var currentWinner: Winner = .primary

    /// Whether language detection is complete and we've committed to one recognizer.
    private var committed = false

    /// Minimum characters before we commit to a language.
    private static let commitThreshold = 12

    /// Frozen prefix from word deletions. New recognizer output is appended after this.
    private var frozenPrefix = ""

    /// Pick the best transcript. During the detection phase, compare confidence.
    /// Once the winner accumulates enough text, commit and kill the loser.
    private func pickBestTranscript() {
        var raw: String
        if secondaryRequest == nil {
            // Single language mode
            raw = primaryTranscript
        } else if committed {
            // Already committed — only use the winner
            switch currentWinner {
            case .primary: raw = primaryTranscript
            case .secondary: raw = secondaryTranscript
            }
        } else {
            // Detection phase: pick whichever has higher confidence
            if secondaryConfidence > primaryConfidence && !secondaryTranscript.isEmpty {
                currentWinner = .secondary
                raw = secondaryTranscript
            } else if !primaryTranscript.isEmpty {
                currentWinner = .primary
                raw = primaryTranscript
            } else {
                raw = ""
            }

            // Commit once the winner has enough text
            let winnerText = currentWinner == .primary ? primaryTranscript : secondaryTranscript
            if winnerText.count >= Self.commitThreshold {
                committed = true
                // Kill the losing recognizer to stop it from producing garbage
                switch currentWinner {
                case .primary:
                    secondaryRequest?.endAudio()
                    secondaryTask?.cancel()
                    secondaryRequest = nil
                    secondaryTask = nil
                    logger.info("Committed to primary language")
                case .secondary:
                    primaryRequest?.endAudio()
                    primaryTask?.cancel()
                    primaryRequest = nil
                    primaryTask = nil
                    logger.info("Committed to secondary language")
                }
            }
        }

        // Prepend frozen prefix (from word deletions) to new recognizer output
        if frozenPrefix.isEmpty {
            transcript = raw
        } else if raw.isEmpty {
            transcript = frozenPrefix
        } else {
            transcript = frozenPrefix + " " + raw
        }
    }

    /// Restart recognition tasks while keeping the audio engine running.
    /// Called after word deletion to start fresh so deleted words don't reappear.
    private func restartRecognitionTasks() {
        // Cancel current tasks
        primaryRequest?.endAudio()
        primaryTask?.cancel()
        secondaryRequest?.endAudio()
        secondaryTask?.cancel()
        primaryTranscript = ""
        primaryConfidence = 0
        secondaryTranscript = ""
        secondaryConfidence = 0

        // Determine which recognizer(s) to restart
        let primaryLocale = PreferencesManager.shared.voiceLanguage
        let secondaryLocale = PreferencesManager.shared.voiceSecondaryLanguage

        // Start new primary task
        if let rec = recognizer(for: committed && currentWinner == .secondary ? secondaryLocale : primaryLocale) {
            let req = makeRequest()
            primaryRequest = req
            primaryTask = rec.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.isRecording else { return }
                    if let result {
                        self.primaryTranscript = result.bestTranscription.formattedString
                        self.primaryConfidence = self.averageConfidence(result.bestTranscription)
                        self.pickBestTranscript()
                    }
                }
            }
        }

        // If not yet committed to a language, restart secondary too
        if !committed && !secondaryLocale.isEmpty && secondaryLocale != primaryLocale {
            if let rec = recognizer(for: secondaryLocale) {
                let req = makeRequest()
                secondaryRequest = req
                secondaryTask = rec.recognitionTask(with: req) { [weak self] result, error in
                    Task { @MainActor in
                        guard let self, self.isRecording else { return }
                        if let result {
                            self.secondaryTranscript = result.bestTranscription.formattedString
                            self.secondaryConfidence = self.averageConfidence(result.bestTranscription)
                            self.pickBestTranscript()
                        }
                    }
                }
            }
        } else {
            secondaryRequest = nil
            secondaryTask = nil
        }

        logger.info("Restarted recognition tasks after word deletion")
    }

    /// Average confidence across all segments of a transcription.
    private func averageConfidence(_ transcription: SFTranscription) -> Float {
        let segments = transcription.segments
        guard !segments.isEmpty else { return 0 }
        let total = segments.reduce(Float(0)) { $0 + $1.confidence }
        return total / Float(segments.count)
    }
}
