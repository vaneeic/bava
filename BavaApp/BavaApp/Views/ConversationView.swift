import SwiftUI

/// Conversation mode: chat-style caption bubbles for face-to-face use.
struct ConversationView: View {
    @EnvironmentObject var speechService: SpeechRecognitionService
    @AppStorage("conversationFontSize") private var fontSize: Double = 20
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showSaveAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Caption list
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(speechService.captions) { caption in
                                    CaptionBubble(caption: caption, fontSize: fontSize)
                                        .id(caption.id)
                                }

                                // Live interim text
                                if !speechService.currentText.isEmpty {
                                    InterimBubble(text: speechService.currentText, fontSize: fontSize)
                                        .id("interim")
                                }
                            }
                            .padding()
                        }
                        .onChange(of: speechService.captions.count) {
                            withAnimation {
                                if let last = speechService.captions.last {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: speechService.currentText) {
                            withAnimation {
                                proxy.scrollTo("interim", anchor: .bottom)
                            }
                        }
                    }

                    // Bottom bar
                    bottomBar
                }
            }
            .navigationTitle("Gesprek")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !speechService.captions.isEmpty {
                        Button {
                            saveTranscript()
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !speechService.captions.isEmpty {
                        Button {
                            speechService.clearSession()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .alert("Opgeslagen!", isPresented: $showSaveAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Het transcript is opgeslagen in Geschiedenis.")
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 16) {
            // Volume indicator
            if speechService.isListening {
                VolumeMeter(level: speechService.audioLevel)
                    .frame(width: 40, height: 40)
            }

            // Status text
            VStack(alignment: .leading, spacing: 2) {
                Text(speechService.isListening ? "Luistert..." : "Tik om te starten")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let error = speechService.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Mic button
            Button {
                toggleListening()
            } label: {
                ZStack {
                    Circle()
                        .fill(speechService.isListening ? Color.red : Color("AccentColor"))
                        .frame(width: 56, height: 56)

                    Image(systemName: speechService.isListening ? "stop.fill" : "mic.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions

    private func toggleListening() {
        if speechService.isListening {
            speechService.stopListening()
        } else {
            speechService.startListening()
        }
    }

    private func saveTranscript() {
        if let transcript = speechService.createTranscript(mode: "Gesprek") {
            try? TranscriptStorage.shared.save(transcript)
            showSaveAlert = true
        }
    }
}

// MARK: - Caption Bubble

struct CaptionBubble: View {
    let caption: Caption
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption.text)
                .font(.system(size: fontSize))
                .foregroundColor(.primary)

            Text(caption.timestamp, style: .time)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Interim Bubble (live text)

struct InterimBubble: View {
    let text: String
    let fontSize: Double

    var body: some View {
        Text(text)
            .font(.system(size: fontSize))
            .foregroundColor(.secondary)
            .italic()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Color("AccentColor").opacity(0.1),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Volume Meter

struct VolumeMeter: View {
    let level: Float

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 3)

            Circle()
                .trim(from: 0, to: CGFloat(level))
                .stroke(meterColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: level)

            Image(systemName: "waveform")
                .font(.caption)
                .foregroundColor(meterColor)
        }
    }

    private var meterColor: Color {
        if level > 0.6 { return .green }
        if level > 0.3 { return .yellow }
        return .gray
    }
}

#Preview {
    ConversationView()
        .environmentObject(SpeechRecognitionService())
        .preferredColorScheme(.dark)
}
