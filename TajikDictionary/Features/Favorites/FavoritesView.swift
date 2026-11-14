import SwiftData
import SwiftUI

struct FavoritesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteItem.addedAt, order: .reverse) private var favorites: [FavoriteItem]

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
            .navigationDestination(for: Int64.self) { entryId in
                EntryDetailView(entryId: entryId)
            }
        }
    }
}
