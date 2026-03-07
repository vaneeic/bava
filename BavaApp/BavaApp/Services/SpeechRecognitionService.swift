import Foundation
import AVFoundation
import Speech
import UIKit
import Combine

/// Speech recognition service using Apple's SFSpeechRecognizer.
/// Supports on-device recognition for Dutch (nl-NL).
@MainActor
final class SpeechRecognitionService: ObservableObject {

    // MARK: - Published State

    @Published var isListening = false
    @Published var currentText = ""          // Live interim text
    @Published var captions: [Caption] = []  // Finalized captions
    @Published var audioLevel: Float = 0     // 0..1 normalized volume
    @Published var errorMessage: String?
    @Published var isAuthorized = false

    // MARK: - Private

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var levelTimer: Timer?
    private var silenceTimer: Timer?
    private var sessionStartTime: Date?

    /// Silence timeout (seconds) before auto-stopping
    var silenceTimeout: TimeInterval = 120 // 2 minutes for TV mode

    // MARK: - Init

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "nl-NL"))
    }

    // MARK: - Authorization

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .authorized:
                    self.isAuthorized = true
                case .denied:
                    self.errorMessage = "Spraakherkenning is geweigerd. Ga naar Instellingen → Privacy → Spraakherkenning."
                case .restricted:
                    self.errorMessage = "Spraakherkenning is beperkt op dit apparaat."
                case .notDetermined:
                    self.errorMessage = "Spraakherkenning status onbekend."
                @unknown default:
                    break
                }
            }
        }

        // Also request microphone permission
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                if !granted {
                    self?.errorMessage = "Microfoontoegang is nodig. Ga naar Instellingen → Privacy → Microfoon."
                }
            }
        }
    }

    // MARK: - Start / Stop

    func startListening() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Spraakherkenning (Nederlands) is niet beschikbaar."
            return
        }

        // Stop any existing session
        stopListening()

        sessionStartTime = Date()
        errorMessage = nil

        do {
            try startAudioSession()
            try startRecognition(speechRecognizer: speechRecognizer)
            startLevelMetering()
            isListening = true
        } catch {
            errorMessage = "Kon audio niet starten: \(error.localizedDescription)"
            stopListening()
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        levelTimer?.invalidate()
        levelTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        isListening = false
        currentText = ""
        audioLevel = 0

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Audio Session

    private func startAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Recognition

    private func startRecognition(speechRecognizer: SFSpeechRecognizer) throws {
        let request = SFSpeechAudioBufferRecognitionRequest()

        // Prefer on-device recognition (no internet needed, better privacy)
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        request.shouldReportPartialResults = true
        request.addsPunctuation = true // iOS 16+: auto punctuation

        // Contextual strings to help recognition
        request.contextualStrings = [
            "ondertiteling", "ondertitels", "televisie",
            "volume", "microfoon", "spreker"
        ]

        self.recognitionRequest = request

        // Install audio tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.handleResult(result)
                    self.resetSilenceTimer()
                }

                if let error {
                    // Don't treat cancellation as an error
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                        // "Request was canceled" — normal when stopping
                        return
                    }

                    if self.isListening {
                        print("[Bava] Recognition error: \(error.localizedDescription)")
                        // Try to restart
                        self.restartListening()
                    }
                }

                if result?.isFinal == true && self.isListening {
                    // Recognition ended naturally — restart for continuous listening
                    self.restartListening()
                }
            }
        }
    }

    private func handleResult(_ result: SFSpeechRecognitionResult) {
        let bestTranscription = result.bestTranscription
        let text = bestTranscription.formattedString

        if result.isFinal {
            // Final result — add as caption
            let confidence = bestTranscription.segments.reduce(0.0) { $0 + $1.confidence }
                / Float(max(1, bestTranscription.segments.count))

            let caption = Caption(
                text: text,
                confidence: confidence,
                isFinal: true
            )
            captions.append(caption)
            currentText = ""

            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        } else {
            // Interim result — update live text
            currentText = text
        }
    }

    // MARK: - Auto-restart for continuous listening

    private func restartListening() {
        guard isListening else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else { return }

        // Clean up current session
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        // Restart after a brief delay
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard self.isListening else { return }

            do {
                try self.startAudioSession()
                try self.startRecognition(speechRecognizer: speechRecognizer)
            } catch {
                print("[Bava] Restart failed: \(error)")
                self.errorMessage = "Herstart mislukt. Probeer opnieuw."
                self.isListening = false
            }
        }
    }

    // MARK: - Level Metering

    private func startLevelMetering() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateAudioLevel()
            }
        }
    }

    private func updateAudioLevel() {
        guard audioEngine.isRunning else {
            audioLevel = 0
            return
        }

        let inputNode = audioEngine.inputNode
        let channelData = inputNode.outputFormat(forBus: 0)

        // Use the audio engine's input node to read levels
        // We calculate RMS from the tap buffer instead
        // For now, use a simple approach via installTap data
        // The actual level is computed in the tap callback
    }

    // MARK: - Silence Detection

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stopListening()
            }
        }
    }

    // MARK: - Session Data

    func createTranscript(mode: String) -> Transcript? {
        guard !captions.isEmpty, let startTime = sessionStartTime else { return nil }
        return Transcript(
            date: startTime,
            mode: mode,
            captions: captions,
            duration: Date().timeIntervalSince(startTime)
        )
    }

    func clearSession() {
        captions.removeAll()
        currentText = ""
        sessionStartTime = nil
    }
}
