import SwiftUI

struct TopicEntriesView: View {
    let topic: String

    @Environment(\.dictionaryRepository) private var repository
    @Environment(SettingsStore.self) private var settings
    @State private var entries: [SearchResult] = []
    @State private var showGame = false

    var body: some View {
        List(entries) { row in
            NavigationLink(value: row.id) {
                WordRowView(
                    language: row.language,
                    headword: row.headword,
                    pos: row.pos,
                    preview: row.preview
                )
            }
        }
        .listStyle(.plain)
        .navigationTitle(topic.capitalized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showGame = true
                    } label: {
                        Label(String(localized: "Practice"), systemImage: "play.fill")
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showGame) {
            WordGameView(source: .topic(topic))
        }
        .task(id: settings.mode) {
            entries = (try? await repository.entries(inTopic: topic, mode: settings.mode)) ?? []
        }
    }
}
