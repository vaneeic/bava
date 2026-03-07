import SwiftUI

@main
struct BavaApp: App {
    @StateObject private var speechService = SpeechRecognitionService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(speechService)
                .preferredColorScheme(.dark)
                .onAppear {
                    speechService.requestAuthorization()
                }
        }
    }
}
