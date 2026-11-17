import SwiftUI

struct TopicEntriesView: View {
    let topic: String

    @Environment(\.dictionaryRepository) private var repository
    @Environment(SettingsStore.self) private var settings
    @State private var entries: [SearchResult] = []
    @State private var showGame = false

    var body: some View {
        ScrollView {
            if !entries.isEmpty {
                AppCard {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { idx, row in
                        NavigationLink(value: row.id) {
                            HStack {
                                WordRowView(
                                    language: row.language,
                                    headword: row.headword,
                                    pos: row.pos,
                                    preview: row.preview
                                )
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)

                        if idx < entries.count - 1 {
                            Divider().padding(.horizontal, 16)
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(AppTheme.background)
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
