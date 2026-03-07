import Foundation
import AVFoundation
import Speech
import UIKit
import Combine

/// Speech recognition service using Apple's SFSpeechRecognizer.
/// Supports on-device recognition for Dutch (nl-NL).
///
/// Audio operations run on a dedicated serial queue to avoid
/// threading conflicts with AVAudioEngine / AVAudioSession.
@MainActor
final class SpeechRecognitionService: ObservableObject {

    // MARK: - Published State

    @Published var isListening = false
    @Published var currentText = ""          // Live interim text
    @Published var captions: [Caption] = []  // Finalized captions
    @Published var audioLevel: Float = 0     // 0..1 normalized volume
    @Published var errorMessage: String?
    @Published var isAuthorized = false

    // MARK: - Audio Tuning (live-adjustable)

    /// Microphone gain boost (1.0 = normal, up to 10.0)
    @Published var micGain: Float = 2.0

    /// Use voice-optimized audio mode vs raw measurement mode
    @Published var voiceOptimized: Bool = true

    /// Enable noise suppression (via audio session)
    @Published var noiseSuppression: Bool = true

    /// Force on-device recognition (no server)
    @Published var forceOnDevice: Bool = true

    /// Minimum confidence threshold (0..1) — lower = more text shown
    @Published var minConfidence: Float = 0.0

    // MARK: - Private

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?
    private var sessionStartTime: Date?
    private var gainNode: AVAudioMixerNode?

    /// Dedicated serial queue for all audio operations
    private let audioQueue = DispatchQueue(label: "com.icvanee.bava.audio", qos: .userInteractive)

    /// Latest RMS level from the audio tap (written on audio thread, read on main)
    private let _currentLevel = CurrentLevel()

    /// Silence timeout (seconds) before auto-stopping
    var silenceTimeout: TimeInterval = 120 // 2 minutes for TV mode

    // MARK: - Init

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "nl-NL"))
    }

    // MARK: - Authorization (sequential)

    func requestAuthorization() {
        Task {
            // 1. Request speech recognition permission first
            let speechStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }

            switch speechStatus {
            case .authorized:
                break
            case .denied:
                self.errorMessage = "Spraakherkenning is geweigerd. Ga naar Instellingen → Privacy → Spraakherkenning."
                return
            case .restricted:
                self.errorMessage = "Spraakherkenning is beperkt op dit apparaat."
                return
            case .notDetermined:
                self.errorMessage = "Spraakherkenning status onbekend."
                return
            @unknown default:
                return
            }

            // 2. Then request microphone permission
            let micGranted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }

            if micGranted {
                self.isAuthorized = true
            } else {
                self.errorMessage = "Microfoontoegang is nodig. Ga naar Instellingen → Privacy → Microfoon."
            }
        }
    }

    // MARK: - Start / Stop

    func startListening() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Spraakherkenning (Nederlands) is niet beschikbaar."
            return
        }

        guard isAuthorized else {
            errorMessage = "Geef eerst toestemming voor microfoon en spraakherkenning."
            requestAuthorization()
            return
        }

        // Stop any existing session
        stopListeningInternal()

        sessionStartTime = Date()
        errorMessage = nil

        // Start audio on the dedicated queue
        let engine = audioEngine
        let recognizer = speechRecognizer

        audioQueue.async { [weak self] in
            guard let self else { return }

            // Read tuning settings (captured from main thread)
            let currentGain = self.micGain
            let useVoiceMode = self.voiceOptimized
            let useNoiseSuppression = self.noiseSuppression
            let onDevice = self.forceOnDevice

            do {
                // Configure audio session with tuning options
                let audioSession = AVAudioSession.sharedInstance()
                let audioMode: AVAudioSession.Mode = useVoiceMode ? .voiceChat : .measurement
                var sessionOptions: AVAudioSession.CategoryOptions = [.duckOthers]
                if !useNoiseSuppression {
                    sessionOptions.insert(.allowBluetooth)
                }
                try audioSession.setCategory(.record, mode: audioMode, options: sessionOptions)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

                // Create recognition request with tuning
                let request = SFSpeechAudioBufferRecognitionRequest()
                if onDevice && recognizer.supportsOnDeviceRecognition {
                    request.requiresOnDeviceRecognition = true
                }
                request.shouldReportPartialResults = true
                request.addsPunctuation = true
                request.contextualStrings = [
                    "ondertiteling", "ondertitels", "televisie",
                    "volume", "microfoon", "spreker"
                ]

                // Install audio tap with gain boost
                let inputNode = engine.inputNode
                let recordingFormat = inputNode.outputFormat(forBus: 0)
                let levelRef = self._currentLevel

                inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                    // Apply gain boost to audio data before sending to recognizer
                    if currentGain != 1.0, let channelData = buffer.floatChannelData {
                        let frameLength = Int(buffer.frameLength)
                        let channels = Int(buffer.format.channelCount)
                        for ch in 0..<channels {
                            for i in 0..<frameLength {
                                channelData[ch][i] *= currentGain
                            }
                        }
                    }

                    request.append(buffer)

                    // Calculate RMS for volume meter (after gain)
                    guard let channelData = buffer.floatChannelData?[0] else { return }
                    let frameLength = Int(buffer.frameLength)
                    var sum: Float = 0
                    for i in 0..<frameLength {
                        let sample = channelData[i]
                        sum += sample * sample
                    }
                    let rms = sqrt(sum / Float(max(1, frameLength)))
                    let normalized = min(1.0, rms * 3.0)
                    levelRef.value = normalized
                }

                engine.prepare()
                try engine.start()

                // Start recognition task — callback comes on arbitrary thread
                let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    guard let self else { return }
                    self.handleRecognitionCallback(result: result, error: error)
                }

                // Update state on main thread
                DispatchQueue.main.async {
                    self.recognitionRequest = request
                    self.recognitionTask = task
                    self.isListening = true
                    self.startLevelPolling()
                }

            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Kon audio niet starten: \(error.localizedDescription)"
                    self.stopListeningInternal()
                }
            }
        }
    }

    func stopListening() {
        stopListeningInternal()
    }

    private func stopListeningInternal() {
        let engine = audioEngine

        // Stop audio on the audio queue to avoid threading issues
        audioQueue.async {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        isListening = false
        currentText = ""
        audioLevel = 0
    }

    // MARK: - Recognition Callback (called on arbitrary thread)

    private nonisolated func handleRecognitionCallback(result: SFSpeechRecognitionResult?, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if let result {
                self.handleResult(result)
                self.resetSilenceTimer()
            }

            if let error {
                let nsError = error as NSError
                // Code 216 = "Request was canceled" — normal when stopping
                // Code 1110 = "No speech detected"
                if nsError.domain == "kAFAssistantErrorDomain" &&
                    (nsError.code == 216 || nsError.code == 1110) {
                    if nsError.code == 1110 && self.isListening {
                        self.restartListening()
                    }
                    return
                }

                if self.isListening {
                    print("[Bava] Recognition error: \(error.localizedDescription)")
                    self.restartListening()
                }
            }

            if result?.isFinal == true && self.isListening {
                self.restartListening()
            }
        }
    }

    private func handleResult(_ result: SFSpeechRecognitionResult) {
        let bestTranscription = result.bestTranscription
        let text = bestTranscription.formattedString

        if result.isFinal {
            let confidence = bestTranscription.segments.reduce(0.0) { $0 + $1.confidence }
                / Float(max(1, bestTranscription.segments.count))

            // Skip low-confidence results if threshold is set
            guard confidence >= minConfidence else {
                currentText = ""
                return
            }

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
            currentText = text
        }
    }

    /// Restart with new audio settings (call when tuning changes while listening)
    func applyAudioSettings() {
        guard isListening else { return }
        restartListening()
    }

    // MARK: - Auto-restart for continuous listening

    private func restartListening() {
        guard isListening else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else { return }

        let engine = audioEngine

        // Clean up on audio queue
        audioQueue.async { [weak self] in
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        // Restart after a brief delay
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.isListening else { return }

            // Re-trigger startListening (which runs audio setup on audioQueue)
            self.isListening = false // allow startListening to proceed
            self.startListening()
        }
    }

    // MARK: - Level Polling

    private func startLevelPolling() {
        // Use a display-link style timer to poll the audio level
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }

            Task { @MainActor in
                guard self.isListening else {
                    timer.invalidate()
                    self.audioLevel = 0
                    return
                }
                self.audioLevel = self._currentLevel.value
            }
        }
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

// MARK: - Thread-safe audio level container

/// Simple thread-safe container for passing audio level between threads.
private final class CurrentLevel: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Float = 0

    var value: Float {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
