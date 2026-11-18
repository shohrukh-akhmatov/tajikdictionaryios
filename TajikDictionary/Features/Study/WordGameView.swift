import SwiftData
import SwiftUI

enum GameDeckSource: Hashable {
    case smartMix
    case dueReviews
    case weakWords
    case saved
    case topic(String)

    var title: String {
        switch self {
        case .smartMix: return String(localized: "Smart Mix")
        case .dueReviews: return String(localized: "Due Reviews")
        case .weakWords: return String(localized: "Weak Words")
        case .saved: return String(localized: "Saved")
        case .topic(let topic): return TopicLocalization.displayName(for: topic)
        }
    }
}

struct WordGameView: View {
    let source: GameDeckSource

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dictionaryRepository) private var repository
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings

    @Query(sort: \FavoriteItem.addedAt, order: .reverse) private var favorites: [FavoriteItem]
    @Query private var progress: [FlashcardProgress]
    @Query private var dailyLogs: [DailyStudyLog]

    @State private var queue: [GameRoundItem] = []
    @State private var initialCount: Int = 0
    @State private var graduatedCount: Int = 0
    @State private var isLoading = true

    // Active card state
    @State private var cardPresentedAt: Date = .now
    @State private var typedAnswer: String = ""
    @State private var selectedTileIndices: [Int] = []
    @State private var selectedChoice: String?
    @State private var usedHint: Bool = false
    @State private var nearMissTarget: String?
    @State private var showingTeachingSheet = false
    @State private var feedbackBanner: (text: String, isPositive: Bool)?

    // Round metrics
    @State private var comboCount: Int = 0
    @State private var sessionXp: Int = 0
    @State private var firstTryCorrectCount: Int = 0
    @State private var totalAttempts: Int = 0
    @State private var newlyLearnedInRound: Int = 0
    @State private var roundFinished = false
    @State private var lexiconStats: LexiconStats = .fallback
    @State private var speaker = SpeechSpeaker()

    private var currentItem: GameRoundItem? { queue.first }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if initialCount == 0 {
                    ContentUnavailableView(
                        String(localized: "Nothing to practice yet"),
                        systemImage: "sparkles",
                        description: Text(String(localized: "Save a few words or choose Smart Mix to start learning."))
                    )
                } else if roundFinished || queue.isEmpty {
                    roundSummaryView
                } else if let item = currentItem {
                    activeGameView(item: item)
                }
            }
            .navigationTitle(source.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "Close"))
                }
                ToolbarItem(placement: .principal) {
                    StudyLanguageMenu(title: source.title)
                }
                if !roundFinished && initialCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 8) {
                            if comboCount >= 2 {
                                Label("\(comboCount)×", systemImage: "flame.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.orange)
                            }
                            Text("+\(sessionXp) XP")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }
        }
        .task {
            await startNewRound()
        }
        .onChange(of: settings.studyMode) { _, _ in
            // Answers are saved as they happen, so restarting loses nothing.
            speaker.stop()
            Task { await startNewRound() }
        }
        .onDisappear {
            speaker.stop()
        }
    }

    @ViewBuilder
    private func activeGameView(item: GameRoundItem) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    ProgressView(
                        value: Double(graduatedCount),
                        total: Double(max(1, initialCount))
                    )
                    .tint(Color.accentColor)

                    HStack {
                        Text("\(graduatedCount) / \(initialCount) \(String(localized: "learned"))")
                        Spacer()
                        if queue.count > 1 {
                            Text("\(queue.count) \(String(localized: "in queue"))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                // Prompt card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        statusBadge(for: item)
                        if let pos = item.card.pos {
                            Text(pos.label)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let locale = settings.studyMode.partner.speechLocaleIdentifier,
                           !item.card.preview.isEmpty {
                            Button {
                                speaker.speak(
                                    item.card.preview,
                                    localeIdentifier: locale,
                                    rate: settings.avSpeechRate
                                )
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    Text(item.card.preview)
                        .font(.system(size: 24 * settings.fontScale.multiplier, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let cloze = item.clozeSentence {
                        Text(cloze)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(18)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .dismissesKeyboardOnTap()

                if let feedbackBanner {
                    Text(feedbackBanner.text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(feedbackBanner.isPositive ? .green : .orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                if showingTeachingSheet {
                    teachingCardView(item: item)
                } else {
                    challengeArea(item: item)
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    private func statusBadge(for item: GameRoundItem) -> some View {
        let (label, color): (String, Color) = {
            if item.hadMistakeInRound {
                let remaining = max(1, item.requiredCorrectInRound - item.correctInRound)
                return ("\(String(localized: "Practice")) ×\(remaining)", .orange)
            } else if item.isNewWord {
                return (String(localized: "New word"), .blue)
            } else {
                return (String(localized: "Review"), .green)
            }
        }()

        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
    }

    @ViewBuilder
    private func challengeArea(item: GameRoundItem) -> some View {
        switch item.challengeKind {
        case .multipleChoice:
            VStack(spacing: 10) {
                ForEach(item.choices, id: \.self) { choice in
                    Button {
                        handleMultipleChoice(choice, item: item)
                    } label: {
                        HStack {
                            Text(choice)
                                .font(.body.weight(.semibold))
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            choiceBackground(choice: choice, correct: item.card.headword),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedChoice != nil)
                }
            }

        case .wordBuilder:
            VStack(spacing: 14) {
                let built = selectedTileIndices.map { item.tiles[$0] }.joined()
                HStack {
                    Text(built.isEmpty ? String(localized: "Tap letters below to build the word") : built)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(built.isEmpty ? .secondary : .primary)
                    Spacer()
                    if !selectedTileIndices.isEmpty {
                        Button {
                            selectedTileIndices.removeLast()
                        } label: {
                            Image(systemName: "delete.left")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding()
                .frame(minHeight: 58)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], spacing: 8) {
                    ForEach(Array(item.tiles.enumerated()), id: \.offset) { index, tile in
                        let isUsed = selectedTileIndices.contains(index)
                        Button {
                            if !isUsed {
                                selectedTileIndices.append(index)
                            }
                        } label: {
                            Text(tile)
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isUsed)
                        .opacity(isUsed ? 0.35 : 1.0)
                    }
                }

                Button {
                    submitTextAnswer(built, item: item)
                } label: {
                    Text(String(localized: "Check"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedTileIndices.isEmpty)
            }

        case .typing:
            VStack(spacing: 12) {
                TextField(String(localized: "Type Tajik word…"), text: $typedAnswer)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit {
                        submitTextAnswer(typedAnswer, item: item)
                    }

                if item.card.language == .tajik {
                    TajikLettersBar { letter in
                        typedAnswer += letter
                    }
                }

                if let target = nearMissTarget {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Almost! Watch the Tajik letter: \(target)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                        Button {
                            completeAnswer(isCorrect: true, usedHintOrNearMiss: true)
                        } label: {
                            Text("Use “\(target)” & Continue")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                HStack(spacing: 10) {
                    Button {
                        usedHint = true
                        let prefix = String(item.card.headword.prefix(2))
                        if !typedAnswer.lowercased().hasPrefix(prefix.lowercased()) {
                            typedAnswer = prefix
                        }
                    } label: {
                        Label(String(localized: "Hint"), systemImage: "lightbulb")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        submitTextAnswer(typedAnswer, item: item)
                    } label: {
                        Text(String(localized: "Check"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .controlSize(.large)
            }
        }

        // Bottom utility buttons
        HStack {
            Button(role: .destructive) {
                triggerDontKnow()
            } label: {
                Label(String(localized: "I don't know"), systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)

            Spacer()

            if item.isNewWord {
                Button {
                    markAlreadyKnown(item: item)
                } label: {
                    Text(String(localized: "Already know"))
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private func teachingCardView(item: GameRoundItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "Learn this word"), systemImage: "book.pages.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)

            Text(item.card.headword)
                .font(.system(size: 32 * settings.fontScale.multiplier, weight: .bold))

            Text(item.card.preview)
                .font(.title3)
                .foregroundStyle(.secondary)

            if let exampleTg = item.card.exampleTg, !exampleTg.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exampleTg).font(.subheadline.weight(.semibold))
                    if let exP = item.card.examplePartner, !exP.isEmpty {
                        Text(exP).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Text(String(localized: "We'll bring this word back in a few cards so you remember it."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                acknowledgeTeachingAndRequeue()
            } label: {
                Text(String(localized: "Got it, practice again"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(18)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var roundSummaryView: some View {
        let accuracy = totalAttempts > 0 ? Int((Double(firstTryCorrectCount) / Double(totalAttempts) * 100).rounded()) : 100
        let summary = WordGameEngine.computeSummary(
            progress: progress.map(\.snapshot),
            logs: dailyLogs.map(\.snapshot),
            dailyGoal: settings.dailyGoal,
            lexiconStats: lexiconStats,
            placementLevel: settings.placementLevel,
            placementBaselineWords: settings.placementBaselineWords
        )

        return VStack(spacing: 20) {
            Spacer()

            Image(systemName: "trophy.fill")
                .font(.system(size: 56))
                .foregroundStyle(.yellow)

            Text(String(localized: "Round complete!"))
                .font(.largeTitle.bold())

            Text(String(localized: "Every word in this round was practiced until learned."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                statPill(value: "+\(sessionXp)", label: "XP", color: .blue)
                statPill(value: "\(accuracy)%", label: String(localized: "Accuracy"), color: .green)
                statPill(value: "\(summary.currentStreakDays)d", label: String(localized: "Streak"), color: .orange)
            }

            HStack(spacing: 10) {
                Text("\(summary.cefrLevel.rawValue) · \(String(format: "%.1f%%", summary.textRecognitionPercent)) \(String(localized: "Text recognized"))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())

                if summary.todayReviewed >= summary.dailyGoal {
                    Label(String(localized: "Daily goal met"), systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }
            }

            if newlyLearnedInRound > 0 {
                Text("New words started: \(newlyLearnedInRound) · Periodic reviews scheduled automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 10) {
                ShareCardButton(
                    content: .round(
                        xp: sessionXp,
                        accuracy: accuracy,
                        newWords: newlyLearnedInRound,
                        streakDays: summary.currentStreakDays,
                        cefr: summary.cefrLevel.rawValue
                    ),
                    prominent: true
                )
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    Task { await startNewRound() }
                } label: {
                    Text(String(localized: "Play Another Round"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    dismiss()
                } label: {
                    Text(String(localized: "Done"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(24)
    }

    private func statPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func choiceBackground(choice: String, correct: String) -> Color {
        guard let selectedChoice else { return Color.secondary.opacity(0.12) }
        if choice == correct { return Color.green.opacity(0.22) }
        if choice == selectedChoice { return Color.red.opacity(0.22) }
        return Color.secondary.opacity(0.08)
    }

    // MARK: - Actions & Persistence

    private func startNewRound() async {
        isLoading = true
        roundFinished = false
        graduatedCount = 0
        comboCount = 0
        sessionXp = 0
        firstTryCorrectCount = 0
        totalAttempts = 0
        newlyLearnedInRound = 0
        resetCardInputs()

        lexiconStats = (try? await repository.lexiconStats()) ?? .fallback
        let mode = settings.studyMode
        let progressById = Dictionary(uniqueKeysWithValues: progress.map { ($0.entryId, $0.snapshot) })
        let ceilingFreq = settings.hasCompletedPlacement ? settings.placementCeilingFreq : 100
        let pool: [WordCardCandidate]
        let selected: [WordCardCandidate]
        switch source {
        case .smartMix:
            let frontierPool = (try? await repository.learningCandidates(
                topic: nil,
                mode: mode,
                maxFrequency: ceilingFreq,
                limit: 450
            )) ?? []
            let activeIds = progress.filter { !$0.isKnownSkipped && $0.lastReviewedAt != nil }.map(\.entryId)
            let activeCandidates = (try? await repository.learningCandidates(forEntryIds: activeIds, mode: mode)) ?? []
            var seen = Set<Int64>()
            var merged: [WordCardCandidate] = []
            for item in activeCandidates + frontierPool {
                if seen.insert(item.entryId).inserted {
                    merged.append(item)
                }
            }
            if merged.count < WordGameEngine.defaultRoundSize, ceilingFreq < 100 {
                let broad = (try? await repository.learningCandidates(topic: nil, mode: mode, maxFrequency: 100, limit: 200)) ?? []
                for item in broad where seen.insert(item.entryId).inserted {
                    merged.append(item)
                }
            }
            pool = merged
            selected = WordGameEngine.buildRoundQueue(
                candidates: pool,
                progressById: progressById,
                now: .now,
                roundSize: WordGameEngine.defaultRoundSize,
                targetMaxFrequency: ceilingFreq
            )
        case .dueReviews:
            let activeIds = progress.filter { !$0.isKnownSkipped && $0.lastReviewedAt != nil }.map(\.entryId)
            pool = (try? await repository.learningCandidates(forEntryIds: activeIds, mode: mode)) ?? []
            selected = WordGameEngine.buildDueRoundQueue(
                candidates: pool,
                progressById: progressById,
                now: .now,
                roundSize: WordGameEngine.defaultRoundSize
            )
        case .weakWords:
            let weakIds = progress.filter {
                !$0.isKnownSkipped && ($0.lapses > 0 || ($0.lastReviewedAt != nil && $0.masteryStage <= 1) || $0.stabilityDays < 2.0)
            }.map(\.entryId)
            pool = (try? await repository.learningCandidates(forEntryIds: weakIds, mode: mode)) ?? []
            selected = WordGameEngine.buildWeakRoundQueue(
                candidates: pool,
                progressById: progressById,
                roundSize: WordGameEngine.defaultRoundSize
            )
        case .topic(let topic):
            pool = (try? await repository.learningCandidates(topic: topic, mode: mode, limit: 450)) ?? []
            selected = WordGameEngine.buildRoundQueue(
                candidates: pool,
                progressById: progressById,
                now: .now,
                roundSize: WordGameEngine.defaultRoundSize,
                targetMaxFrequency: nil
            )
        case .saved:
            let ids = favorites.map(\.entryId)
            pool = (try? await repository.learningCandidates(forEntryIds: ids, mode: mode)) ?? []
            selected = WordGameEngine.buildRoundQueue(
                candidates: pool,
                progressById: progressById,
                now: .now,
                roundSize: WordGameEngine.defaultRoundSize,
                targetMaxFrequency: nil
            )
        }

        let fallbackDistractors = (try? await repository.topTajikHeadwords(limit: 60)) ?? []
        let items = WordGameEngine.makeRoundItems(
            selected: selected,
            allPool: pool,
            fallbackDistractors: fallbackDistractors,
            progressById: progressById
        )

        queue = items
        initialCount = items.count
        cardPresentedAt = .now
        isLoading = false
    }

    private func handleMultipleChoice(_ choice: String, item: GameRoundItem) {
        selectedChoice = choice
        let isCorrect = choice == item.card.headword
        if isCorrect {
            feedbackBanner = (String(localized: "Correct!"), true)
            Task {
                try? await Task.sleep(for: .milliseconds(320))
                completeAnswer(isCorrect: true, usedHintOrNearMiss: false)
            }
        } else {
            triggerDontKnow()
        }
    }

    private func submitTextAnswer(_ input: String, item: GameRoundItem) {
        KeyboardDismisser.dismiss()
        switch WordGameEngine.checkTypedAnswer(input: input, target: item.card.headword) {
        case .exact:
            nearMissTarget = nil
            completeAnswer(isCorrect: true, usedHintOrNearMiss: usedHint)
        case .tajikLetterNearMiss(let target):
            nearMissTarget = target
            usedHint = true
        case .wrong:
            nearMissTarget = nil
            triggerDontKnow()
        }
    }

    private func triggerDontKnow() {
        KeyboardDismisser.dismiss()
        guard !queue.isEmpty else { return }
        totalAttempts += 1
        comboCount = 0
        showingTeachingSheet = true
        feedbackBanner = nil

        let item = queue[0]
        persistEvaluation(
            card: item.card,
            isCorrect: false,
            usedHintOrNearMiss: false,
            responseMs: elapsedMs(),
            wasRetriedInRound: item.hadMistakeInRound
        )
    }

    private func acknowledgeTeachingAndRequeue() {
        guard !queue.isEmpty else { return }
        var item = queue.removeFirst()
        item.hadMistakeInRound = true
        item.requiredCorrectInRound = 2
        item.correctInRound = 0
        // Next pass uses recognition or builder so the user succeeds and builds confidence
        if item.challengeKind == .typing {
            item.challengeKind = WordGameEngine.challengeKind(for: 1, headword: item.card.headword)
        }
        let insertAt = WordGameEngine.reinsertIndex(remainingCount: queue.count)
        queue.insert(item, at: insertAt)

        resetCardInputs()
        cardPresentedAt = .now
    }

    private func completeAnswer(isCorrect: Bool, usedHintOrNearMiss: Bool) {
        guard !queue.isEmpty else { return }
        var item = queue.removeFirst()
        totalAttempts += 1
        if !item.hadMistakeInRound && isCorrect {
            firstTryCorrectCount += 1
        }
        if isCorrect {
            comboCount += 1
            item.correctInRound += 1
        } else {
            comboCount = 0
        }

        let xp = persistEvaluation(
            card: item.card,
            isCorrect: isCorrect,
            usedHintOrNearMiss: usedHintOrNearMiss,
            responseMs: elapsedMs(),
            wasRetriedInRound: item.hadMistakeInRound
        )
        sessionXp += xp

        if item.correctInRound < item.requiredCorrectInRound {
            // Keep cycling in this round until the user confirms they learned it.
            let insertAt = WordGameEngine.reinsertIndex(remainingCount: queue.count)
            queue.insert(item, at: insertAt)
        } else {
            graduatedCount += 1
        }

        resetCardInputs()
        if queue.isEmpty {
            markRoundCompleted()
            roundFinished = true
        } else {
            cardPresentedAt = .now
        }
    }

    private func markAlreadyKnown(item: GameRoundItem) {
        let now = Date.now
        let future = now.addingTimeInterval(180 * WordGameEngine.daySeconds)
        if let existing = progress.first(where: { $0.entryId == item.card.entryId }) {
            existing.isKnownSkipped = true
            existing.masteryStage = 4
            existing.stabilityDays = 180
            existing.lastReviewedAt = now
            existing.nextReviewAt = future
        } else {
            modelContext.insert(FlashcardProgress(
                entryId: item.card.entryId,
                lang: item.card.language.rawValue,
                headword: item.card.headword,
                preview: item.card.preview,
                repetitions: 1,
                intervalDays: 180,
                easeFactor: 2.5,
                nextReviewAt: future,
                masteryStage: 4,
                stabilityDays: 180,
                lapses: 0,
                lastReviewedAt: now,
                isKnownSkipped: true
            ))
        }
        try? modelContext.save()

        if !queue.isEmpty {
            queue.removeFirst()
            graduatedCount += 1
        }
        resetCardInputs()
        if queue.isEmpty {
            markRoundCompleted()
            roundFinished = true
        } else {
            cardPresentedAt = .now
        }
    }

    @discardableResult
    private func persistEvaluation(
        card: WordCardCandidate,
        isCorrect: Bool,
        usedHintOrNearMiss: Bool,
        responseMs: Int64,
        wasRetriedInRound: Bool
    ) -> Int {
        let now = Date.now
        let existing = progress.first { $0.entryId == card.entryId }
        let (updated, xpAwarded, newlyLearned) = WordGameEngine.evaluateAnswer(
            existing: existing?.snapshot,
            entryId: card.entryId,
            isCorrect: isCorrect,
            usedHintOrNearMiss: usedHintOrNearMiss,
            responseMs: responseMs,
            wasRetriedInRound: wasRetriedInRound,
            now: now
        )

        if let existing {
            existing.masteryStage = updated.masteryStage
            existing.stabilityDays = updated.stabilityDays
            existing.repetitions = updated.repetitions
            existing.lapses = updated.lapses
            existing.lastReviewedAt = updated.lastReviewedAt
            existing.nextReviewAt = updated.nextReviewAt
            existing.intervalDays = max(1, Int(updated.stabilityDays.rounded()))
            existing.preview = card.preview
        } else {
            modelContext.insert(FlashcardProgress(
                entryId: card.entryId,
                lang: card.language.rawValue,
                headword: card.headword,
                preview: card.preview,
                repetitions: updated.repetitions,
                intervalDays: max(1, Int(updated.stabilityDays.rounded())),
                easeFactor: 2.5,
                nextReviewAt: updated.nextReviewAt,
                masteryStage: updated.masteryStage,
                stabilityDays: updated.stabilityDays,
                lapses: updated.lapses,
                lastReviewedAt: updated.lastReviewedAt,
                isKnownSkipped: false
            ))
        }

        if newlyLearned {
            newlyLearnedInRound += 1
        }

        let key = WordGameEngine.dateKey(for: now)
        let activeSecs = Int(min(60, max(1, (responseMs + 500) / 1000)))
        if let today = dailyLogs.first(where: { $0.dateKey == key }) {
            today.wordsReviewed += 1
            if newlyLearned { today.wordsLearned += 1 }
            today.xpEarned += xpAwarded
            today.studySeconds += activeSecs
            if isCorrect { today.correctReviews += 1 }
        } else {
            modelContext.insert(DailyStudyLog(
                dateKey: key,
                wordsReviewed: 1,
                wordsLearned: newlyLearned ? 1 : 0,
                xpEarned: xpAwarded,
                roundsCompleted: 0,
                studySeconds: activeSecs,
                correctReviews: isCorrect ? 1 : 0
            ))
        }

        try? modelContext.save()
        return xpAwarded
    }

    private func markRoundCompleted() {
        let key = WordGameEngine.dateKey(for: .now)
        let bonusXp = 20
        sessionXp += bonusXp
        if let today = dailyLogs.first(where: { $0.dateKey == key }) {
            today.roundsCompleted += 1
            today.xpEarned += bonusXp
        } else {
            modelContext.insert(DailyStudyLog(
                dateKey: key,
                wordsReviewed: 0,
                wordsLearned: 0,
                xpEarned: bonusXp,
                roundsCompleted: 1
            ))
        }
        try? modelContext.save()
    }

    private func resetCardInputs() {
        typedAnswer = ""
        selectedTileIndices = []
        selectedChoice = nil
        usedHint = false
        nearMissTarget = nil
        showingTeachingSheet = false
        feedbackBanner = nil
    }

    private func elapsedMs() -> Int64 {
        Int64(max(0, Date.now.timeIntervalSince(cardPresentedAt) * 1000))
    }
}
