import SwiftData
import SwiftUI

private enum VocabFilter: String, CaseIterable, Identifiable {
    case all
    case due
    case weak
    case learning
    case mastered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return String(localized: "All")
        case .due: return String(localized: "Due")
        case .weak: return String(localized: "Weak")
        case .learning: return String(localized: "Learning")
        case .mastered: return String(localized: "Mastered")
        }
    }
}

struct VocabularyListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FlashcardProgress.nextReviewAt) private var progress: [FlashcardProgress]

    @State private var filter: VocabFilter = .all
    @State private var searchText: String = ""
    @State private var practiceSource: GameDeckSource?

    private var now: Date { .now }

    private var filteredItems: [FlashcardProgress] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return progress.filter { item in
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case .due:
                matchesFilter = !item.isKnownSkipped && item.lastReviewedAt != nil && item.nextReviewAt <= now
            case .weak:
                matchesFilter = !item.isKnownSkipped && (item.lapses > 0 || (item.lastReviewedAt != nil && item.masteryStage <= 1) || item.stabilityDays < 2.0)
            case .learning:
                matchesFilter = !item.isKnownSkipped && item.masteryStage < 4
            case .mastered:
                matchesFilter = item.isKnownSkipped || item.masteryStage >= 4
            }
            guard matchesFilter else { return false }
            guard !trimmed.isEmpty else { return true }
            return item.headword.lowercased().contains(trimmed) || item.preview.lowercased().contains(trimmed)
        }
    }

    private var hasWeakWords: Bool {
        progress.contains { !$0.isKnownSkipped && ($0.lapses > 0 || ($0.lastReviewedAt != nil && $0.masteryStage <= 1) || $0.stabilityDays < 2.0) }
    }

    var body: some View {
        List {
            Section {
                Picker(String(localized: "Filter"), selection: $filter) {
                    ForEach(VocabFilter.allCases) { f in
                        Text(f.title).tag(f)
                    }
                }
                .pickerStyle(.segmented)
            }

            if filteredItems.isEmpty {
                ContentUnavailableView(
                    String(localized: "No words match"),
                    systemImage: "books.vertical",
                    description: Text(String(localized: "Words you study in Word Trainer or Flashcards appear here."))
                )
            } else {
                ForEach(filteredItems) { item in
                    NavigationLink(value: item.entryId) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.headword)
                                    .font(.headline)
                                if !item.preview.isEmpty {
                                    Text(item.preview)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                stageBadge(for: item)
                                Text(dueLabel(for: item))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            queueForPractice(item)
                        } label: {
                            Label(String(localized: "Practice"), systemImage: "arrow.counterclockwise")
                        }
                        .tint(.orange)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: Text(String(localized: "Filter vocabulary")))
        .scrollDismissesKeyboard(.immediately)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle(String(localized: "My Vocabulary"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if hasWeakWords {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Drill Weak")) {
                        practiceSource = .weakWords
                    }
                }
            }
        }
        .fullScreenCover(item: $practiceSource) { source in
            WordGameView(source: source)
        }
    }

    @ViewBuilder
    private func stageBadge(for item: FlashcardProgress) -> some View {
        let (title, color): (String, Color) = {
            if item.isKnownSkipped || item.masteryStage >= 4 {
                return (String(localized: "Mastered"), .green)
            }
            if item.lapses > 0 && item.masteryStage <= 1 {
                return (String(localized: "Weak"), .orange)
            }
            return ("\(String(localized: "Stage")) \(item.masteryStage)/4", .blue)
        }()
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func dueLabel(for item: FlashcardProgress) -> String {
        if item.isKnownSkipped { return String(localized: "Known") }
        if item.nextReviewAt <= now { return String(localized: "Due now") }
        let days = max(1, Int((item.nextReviewAt.timeIntervalSince(now) / WordGameEngine.daySeconds).rounded()))
        return "+\(days)d"
    }

    private func queueForPractice(_ item: FlashcardProgress) {
        item.isKnownSkipped = false
        item.masteryStage = 0
        item.stabilityDays = 0.25
        item.nextReviewAt = .now
        item.lastReviewedAt = item.lastReviewedAt ?? .now
        try? modelContext.save()
    }
}
