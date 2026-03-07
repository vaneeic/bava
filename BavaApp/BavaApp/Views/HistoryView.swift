import SwiftUI

/// Shows saved transcripts with search, share, and delete.
struct HistoryView: View {
    @State private var transcripts: [Transcript] = []
    @State private var searchText = ""
    @State private var selectedTranscript: Transcript?
    @State private var showDeleteAll = false

    private var filteredTranscripts: [Transcript] {
        if searchText.isEmpty {
            return transcripts
        }
        return transcripts.filter {
            $0.fullText.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if transcripts.isEmpty {
                    emptyState
                } else {
                    transcriptList
                }
            }
            .navigationTitle("Geschiedenis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !transcripts.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            showDeleteAll = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .onAppear {
                loadTranscripts()
            }
            .alert("Alles verwijderen?", isPresented: $showDeleteAll) {
                Button("Verwijderen", role: .destructive) {
                    TranscriptStorage.shared.deleteAll()
                    loadTranscripts()
                }
                Button("Annuleren", role: .cancel) {}
            } message: {
                Text("Alle opgeslagen transcripten worden permanent verwijderd.")
            }
            .sheet(item: $selectedTranscript) { transcript in
                TranscriptDetailView(transcript: transcript, onDelete: {
                    TranscriptStorage.shared.delete(transcript)
                    selectedTranscript = nil
                    loadTranscripts()
                })
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Nog geen transcripten")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Start een gesprek of TV-sessie om\nondertitels op te slaan.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Transcript List

    private var transcriptList: some View {
        List {
            ForEach(filteredTranscripts) { transcript in
                Button {
                    selectedTranscript = transcript
                } label: {
                    TranscriptRow(transcript: transcript)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        TranscriptStorage.shared.delete(transcript)
                        loadTranscripts()
                    } label: {
                        Label("Verwijder", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    ShareLink(item: TranscriptStorage.shared.exportText(transcript)) {
                        Label("Deel", systemImage: "square.and.arrow.up")
                    }
                    .tint(.blue)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Zoek in transcripten")
    }

    private func loadTranscripts() {
        transcripts = TranscriptStorage.shared.loadAll()
    }
}

// MARK: - Transcript Row

struct TranscriptRow: View {
    let transcript: Transcript

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "nl-NL")
        return formatter.string(from: transcript.date)
    }

    private var durationText: String {
        let minutes = Int(transcript.duration) / 60
        let seconds = Int(transcript.duration) % 60
        return "\(minutes)m \(seconds)s"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: transcript.mode == "TV" ? "tv" : "bubble.left.and.bubble.right")
                    .foregroundColor(Color("AccentColor"))
                Text(transcript.mode)
                    .font(.subheadline.bold())
                Spacer()
                Text(dateText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(transcript.fullText.prefix(100) + (transcript.fullText.count > 100 ? "..." : ""))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)

            HStack {
                Label(durationText, systemImage: "clock")
                Spacer()
                Label("\(transcript.captions.count) zinnen", systemImage: "text.bubble")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Transcript Detail View

struct TranscriptDetailView: View {
    let transcript: Transcript
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(transcript.captions) { caption in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(caption.text)
                                .font(.body)

                            HStack {
                                Text(caption.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                if caption.confidence > 0 {
                                    Text("(\(Int(caption.confidence * 100))%)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(transcript.mode)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluiten") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: TranscriptStorage.shared.exportText(transcript)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }
}

#Preview {
    HistoryView()
        .preferredColorScheme(.dark)
}
