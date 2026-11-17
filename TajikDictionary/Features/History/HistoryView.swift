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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.background)
                } else {
                    ScrollView {
                        AppCard {
                            ForEach(Array(history.enumerated()), id: \.element.entryId) { idx, item in
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
                                        Image(systemName: "xmark")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .frame(width: 32, height: 32)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(String(localized: "Remove"))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)

                                if idx < history.count - 1 {
                                    Divider().padding(.horizontal, 16)
                                }
                            }
                        }
                        .padding(16)
                    }
                    .background(AppTheme.background)
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
