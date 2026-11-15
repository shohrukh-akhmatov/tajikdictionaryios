import Foundation

/// Challenge style scales with the user's mastery stage for a word.
enum ChallengeKind: String, Sendable, Hashable {
    case multipleChoice
    case wordBuilder
    case typing
}

/// CEFR-aligned Tajik vocabulary proficiency tiers.
enum CefrLevel: String, CaseIterable, Comparable, Sendable {
    case a0 = "A0"
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"
    case b2 = "B2"

    var rank: Int {
        switch self {
        case .a0: return 0
        case .a1: return 1
        case .a2: return 2
        case .b1: return 3
        case .b2: return 4
        }
    }

    static func < (lhs: CefrLevel, rhs: CefrLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    var title: String {
        switch self {
        case .a0: return String(localized: "Starter")
        case .a1: return String(localized: "Elementary")
        case .a2: return String(localized: "Pre-Intermediate")
        case .b1: return String(localized: "Intermediate")
        case .b2: return String(localized: "Upper-Intermediate")
        }
    }

    /// Frequency ceiling in `dictionary.sqlite` (`40..100`) where new Smart Mix words start.
    var recommendedCeilingFrequency: Int {
        switch self {
        case .a0: return 100
        case .a1: return 90
        case .a2: return 82
        case .b1: return 72
        case .b2: return 62
        }
    }

    var baselineKnownWords: Int {
        switch self {
        case .a0: return 0
        case .a1: return 150
        case .a2: return 500
        case .b1: return 1500
        case .b2: return 3200
        }
    }
}

struct LexiconStats: Sendable {
    let totalTajik: Int
    let tier90Count: Int
    let tier80Count: Int
    let tier70Count: Int
    let tierOtherCount: Int

    static let fallback = LexiconStats(
        totalTajik: 16_358,
        tier90Count: 290,
        tier80Count: 1_474,
        tier70Count: 4_536,
        tierOtherCount: 10_058
    )
}

struct FrequencyTierProgress: Identifiable, Sendable {
    let id: String
    let label: String
    let knownCount: Int
    let totalCount: Int
}

struct DailyActivityPoint: Identifiable, Sendable {
    var id: String { dateKey }
    let dateKey: String
    let shortLabel: String
    let wordsReviewed: Int
    let studySeconds: Int
    let metGoal: Bool
}

struct PlacementQuestion: Identifiable, Hashable, Sendable {
    var id: Int64 { candidate.entryId }
    let candidate: WordCardCandidate
    let tier: Int // 1..4
    let choices: [String] // partner-language translations
}

struct PlacementAnswer: Sendable {
    let question: PlacementQuestion
    let isCorrect: Bool
}

struct PlacementResult: Sendable {
    let cefrLevel: CefrLevel
    let correctCount: Int
    let totalCount: Int
    let estimatedKnownWords: Int
    let textRecognitionPercent: Double
    let knownEntryIds: [Int64]
    let focusEntryIds: [Int64]
}

/// Candidate Tajik vocabulary item drawn from the bundled dictionary for a learning round.
struct WordCardCandidate: Identifiable, Hashable, Sendable {
    var id: Int64 { entryId }
    let entryId: Int64
    let language: Language
    let headword: String
    let preview: String
    let pos: PartOfSpeech?
    let frequency: Int
    let topic: String?
    let exampleTg: String?
    let examplePartner: String?
}

/// Pure snapshot of a word's periodic memory state (decoupled from SwiftData for unit testing).
struct WordProgressSnapshot: Hashable, Sendable {
    let entryId: Int64
    var masteryStage: Int
    var stabilityDays: Double
    var repetitions: Int
    var lapses: Int
    var lastReviewedAt: Date?
    var nextReviewAt: Date
    var isKnownSkipped: Bool

    init(
        entryId: Int64,
        masteryStage: Int = 0,
        stabilityDays: Double = 0,
        repetitions: Int = 0,
        lapses: Int = 0,
        lastReviewedAt: Date? = nil,
        nextReviewAt: Date = .distantPast,
        isKnownSkipped: Bool = false
    ) {
        self.entryId = entryId
        self.masteryStage = masteryStage
        self.stabilityDays = stabilityDays
        self.repetitions = repetitions
        self.lapses = lapses
        self.lastReviewedAt = lastReviewedAt
        self.nextReviewAt = nextReviewAt
        self.isKnownSkipped = isKnownSkipped
    }
}

struct DailyStudySnapshot: Hashable, Sendable {
    let dateKey: String
    var wordsReviewed: Int
    var wordsLearned: Int
    var xpEarned: Int
    var roundsCompleted: Int
    var studySeconds: Int = 0
    var correctReviews: Int = 0
}

struct GameRoundItem: Identifiable, Hashable, Sendable {
    var id: Int64 { card.entryId }
    let card: WordCardCandidate
    var challengeKind: ChallengeKind
    let choices: [String]
    let tiles: [String]
    let clozeSentence: String?
    let isNewWord: Bool
    var requiredCorrectInRound: Int = 1
    var correctInRound: Int = 0
    var hadMistakeInRound: Bool = false
}

enum AnswerCheckResult: Equatable, Sendable {
    case exact
    case tajikLetterNearMiss(target: String)
    case wrong
}

struct AchievementBadge: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let unlocked: Bool
}

struct GamificationSummary: Sendable {
    let totalXp: Int
    let level: Int
    let levelTitle: String
    let xpInCurrentLevel: Int
    let xpForNextLevel: Int
    let currentStreakDays: Int
    let longestStreakDays: Int
    let activeDaysCount: Int
    let totalStudySeconds: Int
    let totalReviews: Int
    let overallAccuracyPercent: Int
    let todayReviewed: Int
    let todayLearned: Int
    let dailyGoal: Int
    let encounteredCount: Int
    let learningCount: Int
    let masteredCount: Int
    let dueNowCount: Int
    let estimatedKnownWords: Int
    let textRecognitionPercent: Double
    let cefrLevel: CefrLevel
    let totalLexiconCount: Int
    let tierBreakdown: [FrequencyTierProgress]
    let recent7Days: [DailyActivityPoint]
    let badges: [AchievementBadge]
}

/// Lingvist-inspired periodic memory scheduler, Zipf coverage estimator, and placement engine.
enum WordGameEngine {
    static let daySeconds: TimeInterval = 86_400
    static let defaultRoundSize = 10
    private static let backlogThreshold = 20

    /// ACT-R / forgetting-curve inspired retrieval probability in (0, 1].
    static func retrievalProbability(stabilityDays: Double, elapsedDays: Double) -> Double {
        let safeStability = max(0.25, stabilityDays)
        let safeElapsed = max(0.0, elapsedDays)
        return pow(0.9, safeElapsed / safeStability)
    }

    /// Zipf-calibrated percentage of everyday Tajik text recognized for `effectiveKnownWords`.
    static func textRecognitionPercent(effectiveKnownWords: Double) -> Double {
        guard effectiveKnownWords > 0 else { return 0 }
        let pct = 98.5 * (1.0 - 1.0 / pow(1.0 + effectiveKnownWords / 140.0, 0.68))
        return min(99.0, max(0.0, pct))
    }

    /// Selects a balanced batch of overdue periodic reviews + level-appropriate high-frequency new words.
    static func buildRoundQueue(
        candidates: [WordCardCandidate],
        progressById: [Int64: WordProgressSnapshot],
        now: Date = .now,
        roundSize: Int = defaultRoundSize,
        targetMaxFrequency: Int? = nil
    ) -> [WordCardCandidate] {
        let usable = candidates.filter { !$0.preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !usable.isEmpty, roundSize > 0 else { return [] }

        let active = usable.filter { candidate in
            guard let p = progressById[candidate.entryId] else { return true }
            if p.isKnownSkipped && p.nextReviewAt > now {
                return false
            }
            return true
        }

        let dueSorted = active.compactMap { candidate -> (WordCardCandidate, Double)? in
            guard let p = progressById[candidate.entryId], p.lastReviewedAt != nil else { return nil }
            guard p.nextReviewAt <= now else { return nil }
            let elapsed = now.timeIntervalSince(p.lastReviewedAt ?? now) / daySeconds
            let prob = retrievalProbability(stabilityDays: p.stabilityDays, elapsedDays: elapsed)
            return (candidate, prob)
        }
        .sorted { lhs, rhs in
            if abs(lhs.1 - rhs.1) > 0.0001 { return lhs.1 < rhs.1 }
            return lhs.0.frequency > rhs.0.frequency
        }
        .map(\.0)

        let unstudied = active.filter { candidate in
            let p = progressById[candidate.entryId]
            return p == nil || p?.lastReviewedAt == nil
        }

        // Prioritize words starting right at the user's placement ceiling (if any), then fall back.
        let frontierOrdered: [WordCardCandidate]
        if let ceiling = targetMaxFrequency, ceiling < 100 {
            let atOrBelow = unstudied
                .filter { $0.frequency <= ceiling }
                .sorted { lhs, rhs in
                    if lhs.frequency != rhs.frequency { return lhs.frequency > rhs.frequency }
                    return lhs.entryId < rhs.entryId
                }
            let above = unstudied
                .filter { $0.frequency > ceiling }
                .sorted { lhs, rhs in
                    if lhs.frequency != rhs.frequency { return lhs.frequency > rhs.frequency }
                    return lhs.entryId < rhs.entryId
                }
            frontierOrdered = atOrBelow + above
        } else {
            frontierOrdered = unstudied.sorted { lhs, rhs in
                if lhs.frequency != rhs.frequency { return lhs.frequency > rhs.frequency }
                return lhs.entryId < rhs.entryId
            }
        }

        var picked: [WordCardCandidate] = []
        var pickedIds = Set<Int64>()

        if dueSorted.count >= backlogThreshold {
            for item in dueSorted.prefix(roundSize) {
                picked.append(item)
                pickedIds.insert(item.entryId)
            }
            return picked
        }

        let newQuota: Int
        if dueSorted.isEmpty {
            newQuota = min(roundSize, 8)
        } else {
            newQuota = min(frontierOrdered.count, min(3, max(1, roundSize / 3)))
        }

        let dueTarget = max(0, roundSize - newQuota)
        for item in dueSorted.prefix(dueTarget) {
            picked.append(item)
            pickedIds.insert(item.entryId)
        }

        for item in frontierOrdered where picked.count < roundSize && !pickedIds.contains(item.entryId) {
            picked.append(item)
            pickedIds.insert(item.entryId)
        }

        for item in dueSorted where picked.count < roundSize && !pickedIds.contains(item.entryId) {
            picked.append(item)
            pickedIds.insert(item.entryId)
        }

        if picked.isEmpty {
            let fallback = active.sorted { lhs, rhs in
                let sl = progressById[lhs.entryId]?.stabilityDays ?? 0
                let sr = progressById[rhs.entryId]?.stabilityDays ?? 0
                if abs(sl - sr) > 0.01 { return sl < sr }
                return lhs.frequency > rhs.frequency
            }
            for item in fallback.prefix(roundSize) {
                picked.append(item)
            }
        }

        return picked
    }

    static func challengeKind(for masteryStage: Int, headword: String) -> ChallengeKind {
        let letterCount = headword.trimmingCharacters(in: .whitespacesAndNewlines).count
        switch masteryStage {
        case ...0:
            return .multipleChoice
        case 1:
            return (letterCount >= 2 && letterCount <= 14 && !headword.contains(" "))
                ? .wordBuilder
                : .multipleChoice
        default:
            return .typing
        }
    }

    static func makeRoundItems(
        selected: [WordCardCandidate],
        allPool: [WordCardCandidate],
        fallbackDistractors: [String],
        progressById: [Int64: WordProgressSnapshot]
    ) -> [GameRoundItem] {
        selected.map { card in
            let existing = progressById[card.entryId]
            let stage = existing?.masteryStage ?? 0
            let kind = challengeKind(for: stage, headword: card.headword)
            let choices = makeChoices(for: card, pool: allPool, fallbackDistractors: fallbackDistractors)
            let tiles = makeTiles(for: card.headword)
            let cloze = makeClozeSentence(exampleTg: card.exampleTg, targetHeadword: card.headword)
            return GameRoundItem(
                card: card,
                challengeKind: kind,
                choices: choices,
                tiles: tiles,
                clozeSentence: cloze,
                isNewWord: existing?.lastReviewedAt == nil
            )
        }
    }

    static func makeChoices(
        for card: WordCardCandidate,
        pool: [WordCardCandidate],
        fallbackDistractors: [String]
    ) -> [String] {
        var seenNormalized = Set<String>([card.headword.lowercased()])
        var distractors: [String] = []

        let samePos = pool
            .filter { $0.entryId != card.entryId && $0.pos == card.pos }
            .sorted { abs($0.frequency - card.frequency) < abs($1.frequency - card.frequency) }
        for item in samePos {
            let key = item.headword.lowercased()
            if seenNormalized.insert(key).inserted {
                distractors.append(item.headword)
                if distractors.count == 3 { break }
            }
        }

        if distractors.count < 3 {
            let anyPool = pool
                .filter { $0.entryId != card.entryId }
                .shuffled()
            for item in anyPool {
                let key = item.headword.lowercased()
                if seenNormalized.insert(key).inserted {
                    distractors.append(item.headword)
                    if distractors.count == 3 { break }
                }
            }
        }

        if distractors.count < 3 {
            for word in fallbackDistractors.shuffled() {
                let key = word.lowercased()
                if seenNormalized.insert(key).inserted {
                    distractors.append(word)
                    if distractors.count == 3 { break }
                }
            }
        }

        return ([card.headword] + distractors).shuffled()
    }

    static func makeTiles(for headword: String) -> [String] {
        let chars = Array(headword.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !chars.isEmpty else { return [] }

        let chunkSize = chars.count <= 6 ? 1 : 2
        var tiles: [String] = []
        var idx = 0
        while idx < chars.count {
            let end = min(chars.count, idx + chunkSize)
            tiles.append(String(chars[idx..<end]))
            idx = end
        }
        guard tiles.count > 1 else { return tiles }
        var shuffled = tiles.shuffled()
        if shuffled == tiles {
            shuffled.reverse()
        }
        return shuffled
    }

    static func makeClozeSentence(exampleTg: String?, targetHeadword: String) -> String? {
        guard let example = exampleTg?.trimmingCharacters(in: .whitespacesAndNewlines),
              !example.isEmpty else { return nil }
        let target = targetHeadword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }
        if let range = example.range(of: target, options: .caseInsensitive) {
            return example.replacingCharacters(in: range, with: "____")
        }
        return nil
    }

    static func checkTypedAnswer(input: String, target: String) -> AnswerCheckResult {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return .wrong }

        if trimmedInput.lowercased() == trimmedTarget.lowercased() {
            return .exact
        }

        let normInput = TextNormalizer.searchKey(trimmedInput)
        let normTarget = TextNormalizer.searchKey(trimmedTarget)
        if !normInput.isEmpty && normInput == normTarget {
            return .tajikLetterNearMiss(target: trimmedTarget)
        }
        return .wrong
    }

    static func evaluateAnswer(
        existing: WordProgressSnapshot?,
        entryId: Int64,
        isCorrect: Bool,
        usedHintOrNearMiss: Bool,
        responseMs: Int64,
        wasRetriedInRound: Bool,
        now: Date = .now
    ) -> (updated: WordProgressSnapshot, xpAwarded: Int, newlyLearned: Bool) {
        var state = existing ?? WordProgressSnapshot(entryId: entryId)
        let wasUnlearned = state.lastReviewedAt == nil

        if !isCorrect {
            state.lapses += 1
            state.masteryStage = max(0, state.masteryStage - 1)
            state.stabilityDays = max(0.25, state.stabilityDays * 0.35)
            state.lastReviewedAt = now
            state.nextReviewAt = now.addingTimeInterval(0.25 * daySeconds)
            return (state, 0, false)
        }

        state.repetitions += 1
        let xp: Int
        if wasRetriedInRound || usedHintOrNearMiss {
            state.stabilityDays = state.stabilityDays < 0.5 ? 0.5 : max(1.0, state.stabilityDays * 1.35)
            xp = 5
        } else if responseMs < 5_000 {
            state.masteryStage = min(4, state.masteryStage + 1)
            let base = state.stabilityDays <= 0 ? 1.0 : state.stabilityDays
            state.stabilityDays = max(1.5, base * 2.4)
            xp = 15
        } else {
            state.masteryStage = min(4, state.masteryStage + 1)
            let base = state.stabilityDays <= 0 ? 1.0 : state.stabilityDays
            state.stabilityDays = max(1.0, base * 1.85)
            xp = 10
        }
        state.lastReviewedAt = now
        state.nextReviewAt = now.addingTimeInterval(state.stabilityDays * daySeconds)
        return (state, xp, wasUnlearned)
    }

    /// Re-inserts a missed word a few positions later so the user practices it until learned.
    static func reinsertIndex(remainingCount: Int) -> Int {
        min(3, max(0, remainingCount))
    }

    // MARK: - Placement Level Test

    static func buildPlacementQuestions(pool: [WordCardCandidate]) -> [PlacementQuestion] {
        let usable = pool.filter { !$0.preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let tiers: [(Int, ClosedRange<Int>)] = [
            (1, 90...100),
            (2, 80...89),
            (3, 70...79),
            (4, 40...69),
        ]

        var allPreviews = usable.map(\.preview)
        allPreviews.shuffle()

        var questions: [PlacementQuestion] = []
        var usedIds = Set<Int64>()

        for (tier, range) in tiers {
            let tierWords = usable
                .filter { range.contains($0.frequency) && !usedIds.contains($0.entryId) }
                .shuffled()
            for candidate in tierWords.prefix(3) {
                usedIds.insert(candidate.entryId)
                var seenMeaning = Set<String>([candidate.preview.lowercased()])
                var distractors: [String] = []
                for other in usable.shuffled() where other.entryId != candidate.entryId {
                    let key = other.preview.lowercased()
                    if seenMeaning.insert(key).inserted {
                        distractors.append(other.preview)
                        if distractors.count == 3 { break }
                    }
                }
                let choices = ([candidate.preview] + distractors).shuffled()
                questions.append(PlacementQuestion(candidate: candidate, tier: tier, choices: choices))
            }
        }
        return questions
    }

    static func evaluatePlacement(answers: [PlacementAnswer]) -> PlacementResult {
        func passedTier(_ tier: Int) -> Bool {
            let group = answers.filter { $0.question.tier == tier }
            guard !group.isEmpty else { return false }
            let right = group.filter(\.isCorrect).count
            return right >= max(2, (group.count + 1) / 2)
        }

        let level: CefrLevel
        if passedTier(1) && passedTier(2) && passedTier(3) && passedTier(4) {
            level = .b2
        } else if passedTier(1) && passedTier(2) && passedTier(3) {
            level = .b1
        } else if passedTier(1) && passedTier(2) {
            level = .a2
        } else if passedTier(1) {
            level = .a1
        } else {
            level = .a0
        }

        let correctCount = answers.filter(\.isCorrect).count
        let knownIds = answers.filter(\.isCorrect).map(\.question.candidate.entryId)
        let focusIds = answers.filter { !$0.isCorrect }.map(\.question.candidate.entryId)
        let estimatedWords = level.baselineKnownWords + knownIds.count
        let coverage = textRecognitionPercent(effectiveKnownWords: Double(estimatedWords))

        return PlacementResult(
            cefrLevel: level,
            correctCount: correctCount,
            totalCount: answers.count,
            estimatedKnownWords: estimatedWords,
            textRecognitionPercent: coverage,
            knownEntryIds: knownIds,
            focusEntryIds: focusIds
        )
    }

    // MARK: - Summary & Formatting

    static func dateKey(for date: Date = .now, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 2026
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func formatStudyDuration(seconds: Int) -> String {
        if seconds < 60 {
            return "\(max(0, seconds))s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remMin = minutes % 60
        return remMin > 0 ? "\(hours)h \(remMin)m" : "\(hours)h"
    }

    static func computeSummary(
        progress: [WordProgressSnapshot],
        logs: [DailyStudySnapshot],
        dailyGoal: Int,
        lexiconStats: LexiconStats = .fallback,
        placementLevel: CefrLevel? = nil,
        placementBaselineWords: Int = 0,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> GamificationSummary {
        let totalXp = logs.reduce(0) { $0 + $1.xpEarned }
        let levelStep = 100
        let level = max(1, (totalXp / levelStep) + 1)
        let xpInCurrentLevel = totalXp % levelStep

        let levelTitle: String
        switch level {
        case 1: levelTitle = String(localized: "Novice")
        case 2: levelTitle = String(localized: "Explorer")
        case 3: levelTitle = String(localized: "Learner")
        case 4: levelTitle = String(localized: "Speaker")
        case 5: levelTitle = String(localized: "Scholar")
        default: levelTitle = String(localized: "Master")
        }

        let activeDays = Set(logs.filter { $0.wordsReviewed > 0 }.map(\.dateKey))
        let todayKey = dateKey(for: now, calendar: calendar)
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterdayKey = dateKey(for: yesterdayDate, calendar: calendar)

        var currentStreak = 0
        if activeDays.contains(todayKey) || activeDays.contains(yesterdayKey) {
            var cursor = activeDays.contains(todayKey) ? now : yesterdayDate
            while activeDays.contains(dateKey(for: cursor, calendar: calendar)) {
                currentStreak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = prev
            }
        }

        let sortedKeys = activeDays.sorted()
        var longestStreak = currentStreak
        var running = 0
        var previousDate: Date?
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        for key in sortedKeys {
            if let d = formatter.date(from: key) {
                if let prev = previousDate,
                   let nextExpected = calendar.date(byAdding: .day, value: 1, to: prev),
                   calendar.isDate(d, inSameDayAs: nextExpected) {
                    running += 1
                } else {
                    running = 1
                }
                longestStreak = max(longestStreak, running)
                previousDate = d
            }
        }

        let todayLog = logs.first { $0.dateKey == todayKey }
        let todayReviewed = todayLog?.wordsReviewed ?? 0
        let todayLearned = todayLog?.wordsLearned ?? 0
        let totalStudySeconds = logs.reduce(0) { $0 + $1.studySeconds }
        let totalReviews = logs.reduce(0) { $0 + $1.wordsReviewed }
        let totalCorrect = logs.reduce(0) { $0 + $1.correctReviews }
        let accuracyPct = totalReviews > 0 ? Int((Double(totalCorrect) / Double(totalReviews) * 100.0).rounded()) : 100

        let encountered = progress.filter { $0.lastReviewedAt != nil || $0.isKnownSkipped }.count
        let mastered = progress.filter { $0.masteryStage >= 4 || $0.isKnownSkipped }.count
        let learning = max(0, encountered - mastered)
        let dueNow = progress.filter {
            !$0.isKnownSkipped && $0.lastReviewedAt != nil && $0.nextReviewAt <= now
        }.count

        // Weighted vocabulary size & Zipf text coverage percentage
        let weightedActiveKnown = progress.reduce(0.0) { partial, p in
            if p.isKnownSkipped || p.masteryStage >= 4 { return partial + 1.0 }
            if p.masteryStage >= 2 { return partial + 0.75 }
            if p.masteryStage == 1 { return partial + 0.45 }
            if p.lastReviewedAt != nil { return partial + 0.2 }
            return partial
        }
        let effectiveKnown = Double(placementBaselineWords) + weightedActiveKnown
        let estimatedKnownWords = Int(effectiveKnown.rounded())
        let coveragePct = textRecognitionPercent(effectiveKnownWords: effectiveKnown)

        // CEFR level combines placement test result & earned mastery
        let vocabCefr: CefrLevel
        switch estimatedKnownWords {
        case 3000...: vocabCefr = .b2
        case 1400...: vocabCefr = .b1
        case 450...: vocabCefr = .a2
        case 120...: vocabCefr = .a1
        default: vocabCefr = .a0
        }
        let cefrLevel = max(placementLevel ?? .a0, vocabCefr)

        // Distribute estimated/active known counts cleanly across frequency tiers
        var remainingCredit = estimatedKnownWords
        let t90Known = min(lexiconStats.tier90Count, remainingCredit)
        remainingCredit = max(0, remainingCredit - t90Known)
        let t80Known = min(lexiconStats.tier80Count, remainingCredit)
        remainingCredit = max(0, remainingCredit - t80Known)
        let t70Known = min(lexiconStats.tier70Count, remainingCredit)
        remainingCredit = max(0, remainingCredit - t70Known)
        let tOtherKnown = min(lexiconStats.tierOtherCount, remainingCredit)

        let tiers = [
            FrequencyTierProgress(id: "t90", label: String(localized: "Core Survival (90–100)"), knownCount: t90Known, totalCount: lexiconStats.tier90Count),
            FrequencyTierProgress(id: "t80", label: String(localized: "Everyday (80–89)"), knownCount: t80Known, totalCount: lexiconStats.tier80Count),
            FrequencyTierProgress(id: "t70", label: String(localized: "Conversational (70–79)"), knownCount: t70Known, totalCount: lexiconStats.tier70Count),
            FrequencyTierProgress(id: "t40", label: String(localized: "Advanced (40–69)"), knownCount: tOtherKnown, totalCount: lexiconStats.tierOtherCount),
        ]

        // Last 7 days activity chart
        let logByKey = Dictionary(uniqueKeysWithValues: logs.map { ($0.dateKey, $0) })
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.dateFormat = "E"
        let recent7: [DailyActivityPoint] = (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let key = dateKey(for: day, calendar: calendar)
            let log = logByKey[key]
            let reviewed = log?.wordsReviewed ?? 0
            return DailyActivityPoint(
                dateKey: key,
                shortLabel: String(dayFormatter.string(from: day).prefix(2)),
                wordsReviewed: reviewed,
                studySeconds: log?.studySeconds ?? 0,
                metGoal: reviewed >= max(1, dailyGoal)
            )
        }

        let badges = [
            AchievementBadge(
                id: "first_word",
                title: String(localized: "First Step"),
                subtitle: String(localized: "Learn your first word"),
                systemImage: "sparkles",
                unlocked: encountered >= 1
            ),
            AchievementBadge(
                id: "ten_words",
                title: String(localized: "10 Words"),
                subtitle: String(localized: "Practice 10 different words"),
                systemImage: "leaf.fill",
                unlocked: encountered >= 10
            ),
            AchievementBadge(
                id: "streak_3",
                title: String(localized: "3-Day Streak"),
                subtitle: String(localized: "Study 3 days in a row"),
                systemImage: "flame.fill",
                unlocked: longestStreak >= 3
            ),
            AchievementBadge(
                id: "streak_7",
                title: String(localized: "Weekly Habit"),
                subtitle: String(localized: "Study 7 days in a row"),
                systemImage: "calendar.badge.checkmark",
                unlocked: longestStreak >= 7
            ),
            AchievementBadge(
                id: "master_25",
                title: String(localized: "Word Master"),
                subtitle: String(localized: "Master 25 Tajik words"),
                systemImage: "crown.fill",
                unlocked: mastered >= 25
            ),
            AchievementBadge(
                id: "reviews_100",
                title: String(localized: "Dedicated"),
                subtitle: String(localized: "Complete 100 word reviews"),
                systemImage: "bolt.fill",
                unlocked: totalReviews >= 100
            ),
        ]

        return GamificationSummary(
            totalXp: totalXp,
            level: level,
            levelTitle: levelTitle,
            xpInCurrentLevel: xpInCurrentLevel,
            xpForNextLevel: levelStep,
            currentStreakDays: currentStreak,
            longestStreakDays: longestStreak,
            activeDaysCount: activeDays.count,
            totalStudySeconds: totalStudySeconds,
            totalReviews: totalReviews,
            overallAccuracyPercent: accuracyPct,
            todayReviewed: todayReviewed,
            todayLearned: todayLearned,
            dailyGoal: max(1, dailyGoal),
            encounteredCount: encountered,
            learningCount: learning,
            masteredCount: mastered,
            dueNowCount: dueNow,
            estimatedKnownWords: estimatedKnownWords,
            textRecognitionPercent: coveragePct,
            cefrLevel: cefrLevel,
            totalLexiconCount: lexiconStats.totalTajik,
            tierBreakdown: tiers,
            recent7Days: recent7,
            badges: badges
        )
    }
}
