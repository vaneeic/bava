import SwiftUI

/// App settings: font size, appearance, audio tuning, about info.
struct SettingsView: View {
    @EnvironmentObject var speechService: SpeechRecognitionService
    @AppStorage("conversationFontSize") private var conversationFontSize: Double = 20
    @AppStorage("tvFontSize") private var tvFontSize: Double = 32
    @AppStorage("tvMaxLines") private var tvMaxLines: Int = 3

    var body: some View {
        NavigationStack {
            Form {
                // Audio fine-tuning — MOST IMPORTANT
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Microfoonversterking")
                            Spacer()
                            Text("\(String(format: "%.1f", speechService.micGain))x")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $speechService.micGain, in: 1...10, step: 0.5)
                            .tint(Color("AccentColor"))
                        Text("Verhoog als de microfoon te zacht is (bv. TV op afstand)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Toggle(isOn: $speechService.voiceOptimized) {
                        VStack(alignment: .leading) {
                            Text("Stemoptimalisatie")
                            Text("Optimaliseert audio voor spraak (echo/ruisfilter)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .tint(Color("AccentColor"))

                    Toggle(isOn: $speechService.noiseSuppression) {
                        VStack(alignment: .leading) {
                            Text("Ruisonderdrukking")
                            Text("Filtert achtergrondgeluid (TV, ventilator)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .tint(Color("AccentColor"))

                    Toggle(isOn: $speechService.forceOnDevice) {
                        VStack(alignment: .leading) {
                            Text("On-device herkenning")
                            Text("Uit = Apple server (nauwkeuriger, internet nodig)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .tint(Color("AccentColor"))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Min. betrouwbaarheid")
                            Spacer()
                            Text("\(Int(speechService.minConfidence * 100))%")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $speechService.minConfidence, in: 0...0.8, step: 0.05)
                            .tint(Color("AccentColor"))
                        Text("Hogere waarde = minder maar betrouwbaardere tekst")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // Live volume meter
                    if speechService.isListening {
                        HStack {
                            Text("Volume")
                            Spacer()
                            VolumeMeter(level: speechService.audioLevel)
                                .frame(width: 40, height: 40)
                            Text("\(Int(speechService.audioLevel * 100))%")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                    }

                    // Apply button when listening
                    if speechService.isListening {
                        Button {
                            speechService.applyAudioSettings()
                        } label: {
                            Label("Instellingen toepassen", systemImage: "arrow.clockwise")
                        }
                        .tint(Color("AccentColor"))
                    }
                } header: {
                    Label("Geluid Fine-tuning", systemImage: "waveform.circle")
                } footer: {
                    Text("Wijzig versterking en modus, druk dan op 'Toepassen' om opnieuw te starten met de nieuwe instellingen.")
                }

                // Conversation settings
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lettergrootte: \(Int(conversationFontSize))pt")
                        Slider(value: $conversationFontSize, in: 14...40, step: 1)
                            .tint(Color("AccentColor"))
                    }
                } header: {
                    Label("Gesprek", systemImage: "bubble.left.and.bubble.right")
                }

                // TV settings
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lettergrootte: \(Int(tvFontSize))pt")
                        Slider(value: $tvFontSize, in: 16...72, step: 2)
                            .tint(Color("AccentColor"))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Max regels: \(tvMaxLines)")
                        Slider(value: Binding(
                            get: { Double(tvMaxLines) },
                            set: { tvMaxLines = Int($0) }
                        ), in: 1...6, step: 1)
                            .tint(Color("AccentColor"))
                    }
                } header: {
                    Label("TV Modus", systemImage: "tv")
                }

                // Data
                Section {
                    let count = TranscriptStorage.shared.loadAll().count
                    HStack {
                        Text("Opgeslagen transcripten")
                        Spacer()
                        Text("\(count)")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("Opslag", systemImage: "internaldrive")
                }

                // About
                Section {
                    HStack {
                        Text("Versie")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Over Bava")
                            .font(.headline)
                        Text("Bava biedt live Nederlandse ondertiteling voor doven en slechthorenden. Gebruik de Gesprek-modus voor face-to-face communicatie of de TV-modus om ondertitels weer te geven op een scherm naast de televisie.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Spraakherkenning")
                        Spacer()
                        Text("On-device (Apple)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Taal")
                        Spacer()
                        Text("Nederlands (nl-NL)")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("Info", systemImage: "info.circle")
                }

                // Privacy
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Privacy")
                            .font(.headline)
                        Text("Alle spraakherkenning gebeurt lokaal op je apparaat. Er worden geen audio-opnamen naar servers gestuurd. Transcripten worden alleen lokaal opgeslagen.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("Privacy", systemImage: "lock.shield")
                }
            }
            .navigationTitle("Instellingen")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
