import SwiftUI

struct TopicEntriesView: View {
    let topic: String

    @Environment(\.dictionaryRepository) private var repository
    @Environment(SettingsStore.self) private var settings
    @State private var entries: [SearchResult] = []

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
                    NavigationLink {
                        StudyView(initialTopic: topic)
                    } label: {
                        Label(String(localized: "Study"), systemImage: "graduationcap")
                    }
                }
            }
        }
        .task(id: settings.mode) {
            entries = (try? await repository.entries(inTopic: topic, mode: settings.mode)) ?? []
        }
    }
}
