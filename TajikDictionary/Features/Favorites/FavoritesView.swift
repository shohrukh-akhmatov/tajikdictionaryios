import SwiftData
import SwiftUI

struct FavoritesView: View {
    @Environment(\.modelContext) private var modelContext
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
                } else {
                    List {
                        ForEach(favorites) { item in
                            NavigationLink(value: item.entryId) {
                                WordRowView(
                                    language: item.language,
                                    headword: item.headword,
                                    pos: nil,
                                    preview: item.preview
                                )
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                modelContext.delete(favorites[index])
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(String(localized: "Saved"))
            .toolbar {
                if !favorites.isEmpty {
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
                WordGameView(source: .saved)
            }
            .navigationDestination(for: Int64.self) { entryId in
                EntryDetailView(entryId: entryId)
            }
        }
    }
}
