import SwiftUI

/// App settings: font size, appearance, about info.
struct SettingsView: View {
    @AppStorage("conversationFontSize") private var conversationFontSize: Double = 20
    @AppStorage("tvFontSize") private var tvFontSize: Double = 32
    @AppStorage("tvMaxLines") private var tvMaxLines: Int = 3

    var body: some View {
        NavigationStack {
            Form {
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
