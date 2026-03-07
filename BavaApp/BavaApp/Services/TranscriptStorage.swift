import Foundation

/// Persists transcripts to disk using JSON files in the app's documents directory.
final class TranscriptStorage: @unchecked Sendable {

    static let shared = TranscriptStorage()

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var storageURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Transcripts", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - CRUD

    func save(_ transcript: Transcript) throws {
        let url = storageURL.appendingPathComponent("\(transcript.id.uuidString).json")
        let data = try encoder.encode(transcript)
        try data.write(to: url, options: .atomic)
    }

    func loadAll() -> [Transcript] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: storageURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Transcript? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Transcript.self, from: data)
            }
            .sorted { $0.date > $1.date }
    }

    func delete(_ transcript: Transcript) {
        let url = storageURL.appendingPathComponent("\(transcript.id.uuidString).json")
        try? fileManager.removeItem(at: url)
    }

    func deleteAll() {
        let transcripts = loadAll()
        for t in transcripts {
            delete(t)
        }
    }

    /// Full text export for sharing
    func exportText(_ transcript: Transcript) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale(identifier: "nl-NL")

        var lines: [String] = []
        lines.append("Bava Transcript")
        lines.append("Datum: \(dateFormatter.string(from: transcript.date))")
        lines.append("Modus: \(transcript.mode)")

        if transcript.duration > 0 {
            let minutes = Int(transcript.duration) / 60
            let seconds = Int(transcript.duration) % 60
            lines.append("Duur: \(minutes)m \(seconds)s")
        }

        lines.append("")
        lines.append(transcript.fullText)
        return lines.joined(separator: "\n")
    }
}
