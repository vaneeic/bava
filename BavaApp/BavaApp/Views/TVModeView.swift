import SwiftUI

/// Immersive TV mode: fullscreen subtitles on a black background.
/// Designed to be placed under or next to a TV as a live captioning display.
struct TVModeView: View {
    @EnvironmentObject var speechService: SpeechRecognitionService
    @AppStorage("tvFontSize") private var fontSize: Double = 32
    @AppStorage("tvMaxLines") private var maxLines: Int = 3
    @AppStorage("captionHoldTime") private var captionHoldTime: Double = 0
    @AppStorage("subtitleBackground") private var subtitleBackground: Bool = true
    @State private var showControls = true
    @State private var showSettings = false
    @State private var controlsTimer: Timer?
    @State private var isImmersive = false

    // Show last N captions + current interim text with STABLE IDs
    private var displayLines: [DisplayLine] {
        var lines: [DisplayLine] = []

        // Filter by hold time if set
        var recentCaptions = speechService.captions
        if captionHoldTime > 0 {
            let cutoff = Date().addingTimeInterval(-captionHoldTime)
            recentCaptions = recentCaptions.filter { $0.timestamp > cutoff }
        }

        // Add last finalized captions — use caption.id for stable identity
        let recent = Array(recentCaptions.suffix(maxLines))
        for caption in recent {
            lines.append(DisplayLine(id: caption.id.uuidString, text: caption.text, isFinal: true))
        }

        // Add current interim text — fixed ID so it doesn't flicker
        if !speechService.currentText.isEmpty {
            lines.append(DisplayLine(id: "interim", text: speechService.currentText, isFinal: false))
        }

        // Keep only last maxLines
        return Array(lines.suffix(maxLines))
    }

    var body: some View {
        ZStack {
            // Black background
            Color.black
                .ignoresSafeArea()
                .onTapGesture {
                    toggleControls()
                }

            // Subtitles at bottom
            VStack {
                Spacer()

                VStack(alignment: .center, spacing: 8) {
                    ForEach(displayLines) { line in
                        Text(line.text)
                            .font(.system(size: fontSize, weight: .medium))
                            .foregroundColor(line.isFinal ? .white : .white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, subtitleBackground ? 16 : 0)
                            .padding(.vertical, subtitleBackground ? 6 : 0)
                            .background(
                                subtitleBackground
                                    ? Color.black.opacity(0.7)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .shadow(color: .black, radius: subtitleBackground ? 0 : 4, x: 0, y: 2)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, isImmersive ? 40 : 100)
                .animation(.easeInOut(duration: 0.3), value: displayLines)
            }

            // Volume indicator strip at very bottom
            if speechService.isListening {
                VStack {
                    Spacer()
                    GeometryReader { geo in
                        Rectangle()
                            .fill(volumeColor)
                            .frame(
                                width: geo.size.width * CGFloat(speechService.audioLevel),
                                height: 3
                            )
                    }
                    .frame(height: 3)
                }
                .ignoresSafeArea()
            }

            // Controls overlay
            if showControls {
                VStack {
                    HStack {
                        // Status
                        HStack(spacing: 8) {
                            Circle()
                                .fill(speechService.isListening ? Color.green : Color.red)
                                .frame(width: 10, height: 10)
                            Text(speechService.isListening ? "Luistert..." : "Gestopt")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        Spacer()

                        // Settings button
                        Button {
                            showSettings.toggle()
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.8))
                                .padding(8)
                        }

                        // Exit immersive
                        if isImmersive {
                            Button {
                                exitImmersive()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(8)
                            }
                        }
                    }
                    .padding()

                    Spacer()
                }
                .transition(.opacity)
            }

            // Start/Stop button (always visible)
            VStack {
                Spacer()

                HStack {
                    Spacer()

                    Button {
                        toggleListening()
                    } label: {
                        Image(systemName: speechService.isListening ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(speechService.isListening ? .red : .green)
                            .shadow(color: .black.opacity(0.5), radius: 8)
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
            }

            // Settings panel
            if showSettings {
                settingsPanel
                    .transition(.move(edge: .trailing))
            }

            // Error message
            if let error = speechService.errorMessage {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.white)
                        .padding()
                        .background(.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                        .padding()
                    Spacer()
                }
                .onTapGesture {
                    speechService.errorMessage = nil
                }
            }
        }
        .statusBarHidden(isImmersive)
        .onAppear {
            isImmersive = true
            startAutoHide()
        }
        .onDisappear {
            controlsTimer?.invalidate()
        }
    }

    // MARK: - Settings Panel

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Text("TV Instellingen")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button { showSettings = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                Divider().background(Color.white.opacity(0.2))

                // --- AUDIO FINE-TUNING ---
                Text("GELUID")
                    .font(.caption.bold())
                    .foregroundColor(Color("AccentColor"))

                // Mic gain
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "mic.fill")
                        Text("Versterking")
                        Spacer()
                        Text("\(String(format: "%.1f", speechService.micGain))x")
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    Slider(value: $speechService.micGain, in: 1...10, step: 0.5)
                        .tint(Color("AccentColor"))
                }

                // High-pass filter
                Toggle(isOn: $speechService.highPassEnabled) {
                    HStack {
                        Image(systemName: "waveform.path")
                        Text("High-pass filter")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                }
                .tint(Color("AccentColor"))

                if speechService.highPassEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Cutoff")
                            Spacer()
                            Text("\(Int(speechService.highPassFrequency)) Hz")
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        Slider(value: $speechService.highPassFrequency, in: 50...500, step: 10)
                            .tint(Color("AccentColor"))
                    }
                }

                // Voice optimization toggle
                Toggle(isOn: $speechService.voiceOptimized) {
                    HStack {
                        Image(systemName: "waveform.badge.mic")
                        Text("Stemoptimalisatie")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                }
                .tint(Color("AccentColor"))

                // Noise gate
                Toggle(isOn: $speechService.noiseSuppression) {
                    HStack {
                        Image(systemName: "speaker.slash")
                        Text("Ruisonderdrukking")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                }
                .tint(Color("AccentColor"))

                // On-device toggle
                Toggle(isOn: $speechService.forceOnDevice) {
                    HStack {
                        Image(systemName: speechService.forceOnDevice ? "cpu" : "cloud")
                        Text(speechService.forceOnDevice ? "On-device" : "Server")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                }
                .tint(Color("AccentColor"))

                // Min confidence
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "checkmark.seal")
                        Text("Min. betrouwbaarheid")
                        Spacer()
                        Text("\(Int(speechService.minConfidence * 100))%")
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    Slider(value: $speechService.minConfidence, in: 0...0.8, step: 0.05)
                        .tint(Color("AccentColor"))
                }

                // Apply button
                if speechService.isListening {
                    Button {
                        speechService.applyAudioSettings()
                    } label: {
                        Label("Toepassen", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("AccentColor"))
                }

                // Live volume
                if speechService.isListening {
                    HStack {
                        Image(systemName: "speaker.wave.2")
                            .foregroundColor(.white.opacity(0.6))
                        ProgressView(value: Double(speechService.audioLevel))
                            .tint(volumeColor)
                        Text("\(Int(speechService.audioLevel * 100))%")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                }

                Divider().background(Color.white.opacity(0.2))

                // --- HERKENNING ---
                Text("HERKENNING")
                    .font(.caption.bold())
                    .foregroundColor(Color("AccentColor"))

                // Task hint
                VStack(alignment: .leading, spacing: 4) {
                    Text("Herkenningsmodus")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    Picker("", selection: $speechService.taskHint) {
                        Text("Automatisch").tag(0)
                        Text("Dictatie").tag(1)
                        Text("Zoeken").tag(2)
                        Text("Bevestiging").tag(3)
                    }
                    .pickerStyle(.segmented)
                }

                // Punctuation
                Toggle(isOn: $speechService.addsPunctuation) {
                    HStack {
                        Image(systemName: "textformat.abc")
                        Text("Interpunctie")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                }
                .tint(Color("AccentColor"))

                // Custom context strings
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "text.badge.plus")
                        Text("Contextwoorden")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    TextField("namen, programma's...", text: $speechService.customContextStrings)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Text("Kommagescheiden woorden voor betere herkenning")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }

                Divider().background(Color.white.opacity(0.2))

                // --- WEERGAVE ---
                Text("WEERGAVE")
                    .font(.caption.bold())
                    .foregroundColor(Color("AccentColor"))

                // Subtitle background
                Toggle(isOn: $subtitleBackground) {
                    HStack {
                        Image(systemName: "rectangle.fill")
                        Text("Ondertitel achtergrond")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                }
                .tint(Color("AccentColor"))

                // Caption hold time
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "timer")
                        Text(captionHoldTime == 0 ? "Altijd zichtbaar" : "\(Int(captionHoldTime))s")
                        Spacer()
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    Slider(value: $captionHoldTime, in: 0...30, step: 1)
                        .tint(Color("AccentColor"))
                    Text("0 = altijd zichtbaar, anders verdwijnen na X seconden")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Lettergrootte")
                        Spacer()
                        Text("\(Int(fontSize))pt")
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    Slider(value: $fontSize, in: 16...72, step: 2)
                        .tint(Color("AccentColor"))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Max regels")
                        Spacer()
                        Text("\(maxLines)")
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    Slider(value: Binding(
                        get: { Double(maxLines) },
                        set: { maxLines = Int($0) }
                    ), in: 1...6, step: 1)
                        .tint(Color("AccentColor"))
                }
            }
            .padding(20)
        }
        .frame(width: 300)
        .frame(maxHeight: 500)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 16)
    }

    // MARK: - Helpers

    private var volumeColor: Color {
        let level = speechService.audioLevel
        if level > 0.6 { return .green }
        if level > 0.3 { return .yellow }
        return .gray
    }

    private func toggleListening() {
        if speechService.isListening {
            speechService.stopListening()
        } else {
            speechService.startListening()
        }
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showControls.toggle()
        }
        if showControls {
            startAutoHide()
        }
    }

    private func startAutoHide() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
            Task { @MainActor in
                if !showSettings {
                    withAnimation {
                        showControls = false
                    }
                }
            }
        }
    }

    private func exitImmersive() {
        isImmersive = false
    }
}

// MARK: - Display Line Model

private struct DisplayLine: Identifiable, Equatable {
    let id: String     // Stable ID from caption.id or "interim"
    let text: String
    let isFinal: Bool
}

#Preview {
    TVModeView()
        .environmentObject(SpeechRecognitionService())
}
