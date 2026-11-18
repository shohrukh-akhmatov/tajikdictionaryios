import SwiftData
import SwiftUI

struct StudyCard: Identifiable {
    var id: Int64 { entryId }
    let entryId: Int64
    let language: Language
    let headword: String
    let preview: String
}

struct StudyView: View {
    var initialTopic: String? = nil

    @Environment(\.dictionaryRepository) private var repository
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings

    @Query(sort: \FavoriteItem.addedAt, order: .reverse) private var favorites: [FavoriteItem]
    @Query private var progress: [FlashcardProgress]
    @Query private var dailyLogs: [DailyStudyLog]

    @State private var selectedTopic: String?
    @State private var topics: [TopicCount] = []
    @State private var cards: [StudyCard] = []
    @State private var currentIndex = 0
    @State private var flipped = false
    @State private var reviewedCount = 0
    @State private var cardPresentedAt: Date = .now

    init(initialTopic: String? = nil) {
        self.initialTopic = initialTopic
        _selectedTopic = State(initialValue: initialTopic)
    }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    deckPill(title: String(localized: "Saved"), active: selectedTopic == nil) {
                        selectedTopic = nil
                    }
                    ForEach(topics) { item in
                        deckPill(title: TopicLocalization.displayName(for: item.topic), active: selectedTopic == item.topic) {
                            selectedTopic = item.topic
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 8)

            if cards.isEmpty {
                ContentUnavailableView(
                    String(localized: "Nothing to study yet"),
                    systemImage: "graduationcap",
                    description: Text(String(localized: "Save a few words with the star icon or pick a topic above."))
                )
            } else if currentIndex >= cards.count {
                ContentUnavailableView {
                    Label(String(localized: "Session complete!"), systemImage: "checkmark.circle.fill")
                } description: {
                    Text("You reviewed \(reviewedCount) cards.")
                } actions: {
                    Button(String(localized: "Study Again")) {
                        currentIndex = 0
                        reviewedCount = 0
                        flipped = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                let card = cards[currentIndex]
                ProgressView(value: Double(currentIndex), total: Double(cards.count))
                    .padding(.horizontal)

                Text("\(currentIndex + 1) / \(cards.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                VStack(spacing: 14) {
                    LanguageTag(language: card.language)
                    Text(card.headword)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                    if card.language == .tajik {
                        let latin = TajikTransliterator.toLatin(card.headword)
                        if !latin.isEmpty {
                            Text("/\(latin)/")
                                .font(.headline.italic())
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                    if flipped {
                        Text(card.preview.isEmpty ? "—" : card.preview)
                            .font(.title3)
                            .foregroundStyle(AppTheme.accent)
                            .multilineTextAlignment(.center)
                    } else {
                        Text(String(localized: "Tap card to reveal translation"))
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppTheme.border.opacity(0.7), lineWidth: 1)
                )
                .padding(.horizontal)
                .onTapGesture {
                    flipped.toggle()
                }

                Spacer()

                if !flipped {
                    Button {
                        flipped = true
                    } label: {
                        Text(String(localized: "Show Answer"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal)
                } else {
                    HStack(spacing: 10) {
                        Button(role: .destructive) { grade(card, .again) } label: {
                            Text(String(localized: "Again")).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button { grade(card, .good) } label: {
                            Text(String(localized: "Good")).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button { grade(card, .easy) } label: {
                            Text(String(localized: "Easy")).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.large)
                    .padding(.horizontal)
                }
            }
        }
        .padding(.bottom, 16)
        .background(AppTheme.background)
        .navigationTitle(selectedTopic.map { String(localized: "Study: \(TopicLocalization.displayName(for: $0))") } ?? String(localized: "Flashcards"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            topics = (try? await repository.topics()) ?? []
            await reloadCards()
        }
        .onChange(of: selectedTopic) { _, _ in
            Task { await reloadCards() }
        }
        .onChange(of: settings.studyMode) { _, _ in
            Task { await reloadCards() }
        }
    }

    @ViewBuilder
    private func deckPill(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(active ? "✓ \(title)" : title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(active ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func reloadCards() async {
        let now = Date.now
        let progressById = Dictionary(uniqueKeysWithValues: progress.map { ($0.entryId, $0) })
        let raw: [StudyCard]
        if let topic = selectedTopic {
            let rows = (try? await repository.entries(inTopic: topic, mode: settings.studyMode)) ?? []
            raw = rows.map { StudyCard(entryId: $0.id, language: $0.language, headword: $0.headword, preview: $0.preview) }
        } else {
            raw = favorites.map { StudyCard(entryId: $0.entryId, language: $0.language, headword: $0.headword, preview: $0.preview) }
        }
        let sorted = raw.sorted {
            (progressById[$0.entryId]?.nextReviewAt ?? .distantPast) < (progressById[$1.entryId]?.nextReviewAt ?? .distantPast)
        }
        let due = sorted.filter { (progressById[$0.entryId]?.nextReviewAt ?? .distantPast) <= now }
        cards = due.isEmpty ? sorted : due
        currentIndex = 0
        flipped = false
        reviewedCount = 0
        cardPresentedAt = .now
    }

    private func grade(_ card: StudyCard, _ rating: ReviewRating) {
        let now = Date.now
        let responseMs = Int64(max(0, now.timeIntervalSince(cardPresentedAt) * 1000))
        let existing = progress.first { $0.entryId == card.entryId }
        let currentState = existing.map {
            FlashcardState(repetitions: $0.repetitions, intervalDays: $0.intervalDays, easeFactor: $0.easeFactor)
        } ?? FlashcardState()
        let (nextState, due) = FlashcardScheduler.next(current: currentState, rating: rating, now: now)
        let eval = WordGameEngine.evaluateClassicFlashcard(
            existing: existing?.snapshot,
            entryId: card.entryId,
            rating: rating,
            intervalDays: nextState.intervalDays,
            nextDue: due,
            now: now
        )

        if let existing {
            existing.repetitions = nextState.repetitions
            existing.intervalDays = nextState.intervalDays
            existing.easeFactor = nextState.easeFactor
            existing.nextReviewAt = due
            existing.masteryStage = eval.updated.masteryStage
            existing.stabilityDays = eval.updated.stabilityDays
            existing.lapses = eval.updated.lapses
            existing.lastReviewedAt = eval.updated.lastReviewedAt
            existing.isKnownSkipped = false
            existing.preview = card.preview
        } else {
            modelContext.insert(FlashcardProgress(
                entryId: card.entryId,
                lang: card.language.rawValue,
                headword: card.headword,
                preview: card.preview,
                repetitions: nextState.repetitions,
                intervalDays: nextState.intervalDays,
                easeFactor: nextState.easeFactor,
                nextReviewAt: due,
                masteryStage: eval.updated.masteryStage,
                stabilityDays: eval.updated.stabilityDays,
                lapses: eval.updated.lapses,
                lastReviewedAt: eval.updated.lastReviewedAt,
                isKnownSkipped: false
            ))
        }

        let key = WordGameEngine.dateKey(for: now)
        let activeSecs = Int(min(60, max(1, (responseMs + 500) / 1000)))
        if let today = dailyLogs.first(where: { $0.dateKey == key }) {
            today.wordsReviewed += 1
            if eval.newlyLearned { today.wordsLearned += 1 }
            today.xpEarned += eval.xpAwarded
            today.studySeconds += activeSecs
            if eval.isCorrect { today.correctReviews += 1 }
        } else {
            modelContext.insert(DailyStudyLog(
                dateKey: key,
                wordsReviewed: 1,
                wordsLearned: eval.newlyLearned ? 1 : 0,
                xpEarned: eval.xpAwarded,
                roundsCompleted: 0,
                studySeconds: activeSecs,
                correctReviews: eval.isCorrect ? 1 : 0
            ))
        }
        try? modelContext.save()

        reviewedCount += 1
        currentIndex += 1
        flipped = false
        cardPresentedAt = .now
    }
}
