import Foundation
import AVFoundation
import Speech

/// Caption model — a single recognized piece of speech
struct Caption: Identifiable, Codable {
    let id: UUID
    let text: String
    let timestamp: Date
    let confidence: Float
    let isFinal: Bool

    init(text: String, timestamp: Date = Date(), confidence: Float = 0, isFinal: Bool = true) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
        self.confidence = confidence
        self.isFinal = isFinal
    }
}

/// Saved transcript — a complete session
struct Transcript: Identifiable, Codable {
    let id: UUID
    let date: Date
    let mode: String
    let captions: [Caption]
    let duration: TimeInterval

    var fullText: String {
        captions.map(\.text).joined(separator: "\n")
    }

    init(date: Date, mode: String, captions: [Caption], duration: TimeInterval) {
        self.id = UUID()
        self.date = date
        self.mode = mode
        self.captions = captions
        self.duration = duration
    }
}
