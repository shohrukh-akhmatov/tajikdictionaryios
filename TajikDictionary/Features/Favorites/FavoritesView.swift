import SwiftData
import SwiftUI

struct FavoritesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Query(sort: \FavoriteItem.addedAt, order: .reverse) private var favorites: [FavoriteItem]
    @State private var showGame = false

    var body: some View {
        NavigationStack {
            Group {
                if favorites.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No saved words"),
                        systemImage: "star",
                        description: Text(String(localized: "Tap the star on any word to save it here for quick offline review."))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.background)
                } else {
                    ScrollView {
                        AppCard {
                            ForEach(Array(favorites.enumerated()), id: \.element.entryId) { idx, item in
                                HStack(spacing: 8) {
                                    NavigationLink(value: item.entryId) {
                                        WordRowView(
                                            language: item.language,
                                            headword: item.headword,
                                            pos: nil,
                                            preview: item.preview
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        modelContext.delete(item)
                                    } label: {
                                        Image(systemName: "star.fill")
                                            .foregroundStyle(AppTheme.accent)
                                            .frame(width: 32, height: 32)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(String(localized: "Remove"))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)

                                if idx < favorites.count - 1 {
                                    Divider().padding(.horizontal, 16)
                                }
                            }
                        }
                        .padding(16)
                    }
                    .background(AppTheme.background)
                }
            }
            .navigationTitle(String(localized: "Saved"))
            .toolbar {
                if !favorites.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            settings.studyMode = settings.mode
                            showGame = true
                        } label: {
                            Label(String(localized: "Practice"), systemImage: "play.fill")
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showGame) {
                WordGameView(source: .saved)
            }
            .navigationDestination(for: Int64.self) { entryId in
                EntryDetailView(entryId: entryId)
            }
        }
    }
}
