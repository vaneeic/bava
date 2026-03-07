import SwiftUI

/// Immersive TV mode: fullscreen subtitles on a black background.
/// Designed to be placed under or next to a TV as a live captioning display.
struct TVModeView: View {
    @EnvironmentObject var speechService: SpeechRecognitionService
    @AppStorage("tvFontSize") private var fontSize: Double = 32
    @AppStorage("tvMaxLines") private var maxLines: Int = 3
    @State private var showControls = true
    @State private var showSettings = false
    @State private var controlsTimer: Timer?
    @State private var isImmersive = false

    // Show last N captions + current interim text
    private var displayLines: [DisplayLine] {
        var lines: [DisplayLine] = []

        // Add last finalized captions
        let recent = speechService.captions.suffix(maxLines)
        for caption in recent {
            lines.append(DisplayLine(text: caption.text, isFinal: true))
        }

        // Add current interim text
        if !speechService.currentText.isEmpty {
            lines.append(DisplayLine(text: speechService.currentText, isFinal: false))
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
                            .shadow(color: .black, radius: 4, x: 0, y: 2)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, isImmersive ? 40 : 100)
                .animation(.easeInOut(duration: 0.3), value: displayLines.count)
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
        VStack(alignment: .leading, spacing: 20) {
            Text("TV Instellingen")
                .font(.headline)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 8) {
                Text("Lettergrootte: \(Int(fontSize))pt")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                Slider(value: $fontSize, in: 16...72, step: 2)
                    .tint(Color("AccentColor"))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Max regels: \(maxLines)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                Slider(value: Binding(
                    get: { Double(maxLines) },
                    set: { maxLines = Int($0) }
                ), in: 1...6, step: 1)
                    .tint(Color("AccentColor"))
            }

            // On-device status
            HStack {
                Image(systemName: "cpu")
                Text("On-device herkenning")
                    .font(.subheadline)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            .foregroundColor(.white.opacity(0.8))

            Spacer()

            Button("Sluiten") {
                showSettings = false
            }
            .foregroundColor(Color("AccentColor"))
        }
        .padding(24)
        .frame(width: 280)
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

private struct DisplayLine: Identifiable {
    let id = UUID()
    let text: String
    let isFinal: Bool
}

#Preview {
    TVModeView()
        .environmentObject(SpeechRecognitionService())
}
