import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HistoryItem.viewedAt, order: .reverse) private var history: [HistoryItem]
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if history.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No history yet"),
                        systemImage: "clock",
                        description: Text(String(localized: "Words you open will appear here."))
                    )
                } else {
                    List {
                        ForEach(history) { item in
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
                                modelContext.delete(history[index])
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(String(localized: "History"))
            .toolbar {
                if !history.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(String(localized: "Clear")) {
                            showClearConfirm = true
                        }
                    }
                }
            }
            .confirmationDialog(
                String(localized: "Clear history?"),
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Clear"), role: .destructive) {
                    for item in history { modelContext.delete(item) }
                }
            }
            .navigationDestination(for: Int64.self) { entryId in
                EntryDetailView(entryId: entryId)
            }
        }
    }
}
