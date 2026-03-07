import SwiftUI

struct ContentView: View {
    @EnvironmentObject var speechService: SpeechRecognitionService
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ConversationView()
                .tabItem {
                    Label("Gesprek", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(0)

            TVModeView()
                .tabItem {
                    Label("TV", systemImage: "tv")
                }
                .tag(1)

            HistoryView()
                .tabItem {
                    Label("Geschiedenis", systemImage: "clock.arrow.circlepath")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Instellingen", systemImage: "gearshape")
                }
                .tag(3)
        }
        .tint(Color("AccentColor"))
    }
}

#Preview {
    ContentView()
        .environmentObject(SpeechRecognitionService())
        .preferredColorScheme(.dark)
}
