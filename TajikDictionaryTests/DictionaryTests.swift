import CoreSpotlight
import XCTest
@testable import TajikDictionary

final class DictionaryTests: XCTestCase {

    func testNormalizationVectors() {
        let vectors: [(String, String)] = [
            ("Ҳафта", "хафта"),
            ("хӯрдан", "хурдан"),
            ("ҶАВОБ", "чавоб"),
            ("ғамгин", "гамгин"),
            ("қалам", "калам"),
            ("бинӣ", "бини"),
            ("ёрӣ", "ери"),
            ("Чёрный", "черный"),
            ("мой", "мой"),
            ("  кор   кардан ", "кор кардан"),
            ("кор-бор", "кор бор"),
            ("Don't", "dont"),
            ("café", "cafe"),
            ("To Go", "go"),
        ]
        for (input, expected) in vectors {
            XCTAssertEqual(TextNormalizer.searchKey(input), expected, "Failed for \(input)")
        }
    }

    func testLanguageDetection() {
        XCTAssertEqual(LanguageDetector.candidates(for: "hello"), [.english])
        XCTAssertEqual(LanguageDetector.candidates(for: "ҳафта"), [.tajik])
        XCTAssertEqual(LanguageDetector.candidates(for: "цветок"), [.russian])
        XCTAssertEqual(LanguageDetector.candidates(for: "дар"), [.tajik, .russian])
        XCTAssertEqual(LanguageDetector.candidates(for: "123"), Set(Language.allCases))
    }

    func testMixedLanguageSearchAndNormalizationInBundledDatabase() async throws {
        let repo = try DictionaryRepository()

        let darOutcome = try await repo.search(query: "дар", mode: .tjRu)
        let exactDar = darOutcome.results.filter { $0.headword == "дар" }
        XCTAssertTrue(exactDar.contains { $0.language == .tajik })
        XCTAssertTrue(exactDar.contains { $0.language == .russian && $0.preview.contains("тӯҳфа") })

        let foldedOutcome = try await repo.search(query: "хурдан", mode: .tjRu)
        XCTAssertTrue(foldedOutcome.results.contains { $0.language == .tajik && $0.headword == "хӯрдан" })

        let englishOutcome = try await repo.search(query: "go", mode: .tjEn)
        XCTAssertTrue(englishOutcome.results.contains { $0.language == .english && $0.headword == "to go" })

        let wrongMode = try await repo.search(query: "go", mode: .tjRu)
        XCTAssertTrue(wrongMode.results.isEmpty)
        XCTAssertEqual(wrongMode.suggestedMode, .tjEn)
    }

    func testStemmingFuzzyFallbackAndTopics() async throws {
        let repo = try DictionaryRepository()

        let stemOutcome = try await repo.search(query: "хонаҳо", mode: .tjRu)
        XCTAssertEqual(stemOutcome.matchType, .stem)
        XCTAssertTrue(stemOutcome.results.contains { $0.headword == "хона" })

        let verbOutcome = try await repo.search(query: "меравам", mode: .tjRu)
        XCTAssertEqual(verbOutcome.matchType, .stem)
        XCTAssertTrue(verbOutcome.results.contains { $0.headword == "рафтан" })

        let fuzzyOutcome = try await repo.search(query: "салам", mode: .tjRu)
        XCTAssertEqual(fuzzyOutcome.matchType, .fuzzy)
        XCTAssertTrue(fuzzyOutcome.results.contains { $0.headword == "салом" })

        let topics = try await repo.topics()
        XCTAssertFalse(topics.isEmpty)
        XCTAssertTrue(topics.contains { $0.topic == "verbs" })
    }

    func testFlashcardSchedulerSm2Intervals() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let (first, _) = FlashcardScheduler.next(current: FlashcardState(), rating: .good, now: now)
        XCTAssertEqual(first.repetitions, 1)
        XCTAssertEqual(first.intervalDays, 1)

        let (second, _) = FlashcardScheduler.next(current: first, rating: .good, now: now)
        XCTAssertEqual(second.repetitions, 2)
        XCTAssertEqual(second.intervalDays, 6)

        let (third, dueThird) = FlashcardScheduler.next(current: second, rating: .easy, now: now)
        XCTAssertEqual(third.repetitions, 3)
        XCTAssertGreaterThan(third.intervalDays, 6)
        XCTAssertGreaterThan(dueThird, now)

        let (reset, _) = FlashcardScheduler.next(current: third, rating: .again, now: now)
        XCTAssertEqual(reset.repetitions, 0)
        XCTAssertEqual(reset.intervalDays, 0)
    }

    func testFavoritesBackupRoundTripAndDeepLinks() throws {
        let records = [
            FavoritesBackup.Record(
                entryId: 42,
                lang: "tg",
                headword: "китоб",
                preview: "книга; book",
                addedAt: 1_731_000_000_000
            ),
            FavoritesBackup.Record(
                entryId: 108,
                lang: "ru",
                headword: "здравствуйте",
                preview: "салом",
                addedAt: 1_731_000_001_000
            ),
        ]
        let encoded = try FavoritesBackup.encodeRecords(records, exportedAtMs: 1_731_000_002_000)
        let decoded = try FavoritesBackup.decodeRecords(from: encoded)
        XCTAssertEqual(records, decoded)

        XCTAssertEqual(
            SpotlightIndexer.entryId(from: URL(string: "tajikdictionary://entry/42")!),
            42
        )
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "tj.tajikdictionary.entry.231"]
        XCTAssertEqual(SpotlightIndexer.entryId(from: activity), 231)
    }

    func testWordGameQueueAndPeriodicScheduling() {
        let now = Date(timeIntervalSince1970: 1_731_000_000)
        let candidates = [
            WordCardCandidate(entryId: 1, language: .tajik, headword: "салом", preview: "привет", pos: .interjection, frequency: 100, topic: "greetings", exampleTg: "Салом, дӯстам!", examplePartner: "Привет, друг!"),
            WordCardCandidate(entryId: 2, language: .tajik, headword: "хӯрдан", preview: "есть", pos: .verb, frequency: 90, topic: "verbs", exampleTg: nil, examplePartner: nil),
            WordCardCandidate(entryId: 3, language: .tajik, headword: "китоб", preview: "книга", pos: .noun, frequency: 80, topic: "education", exampleTg: nil, examplePartner: nil),
            WordCardCandidate(entryId: 4, language: .tajik, headword: "об", preview: "вода", pos: .noun, frequency: 95, topic: "food", exampleTg: nil, examplePartner: nil),
        ]

        // Entry 2 is overdue, others are new; due word must appear in queue alongside high-frequency new words.
        let overdue = WordProgressSnapshot(
            entryId: 2,
            masteryStage: 1,
            stabilityDays: 1.0,
            repetitions: 1,
            lapses: 0,
            lastReviewedAt: now.addingTimeInterval(-3 * WordGameEngine.daySeconds),
            nextReviewAt: now.addingTimeInterval(-2 * WordGameEngine.daySeconds)
        )
        let queue = WordGameEngine.buildRoundQueue(
            candidates: candidates,
            progressById: [2: overdue],
            now: now,
            roundSize: 3
        )
        XCTAssertEqual(queue.count, 3)
        XCTAssertTrue(queue.contains { $0.entryId == 2 })
        XCTAssertTrue(queue.contains { $0.entryId == 1 })

        // Fast correct answer grows stability & advances mastery stage.
        let (good, xpGood, newlyLearned) = WordGameEngine.evaluateAnswer(
            existing: nil,
            entryId: 1,
            isCorrect: true,
            usedHintOrNearMiss: false,
            responseMs: 2_500,
            wasRetriedInRound: false,
            now: now
        )
        XCTAssertTrue(newlyLearned)
        XCTAssertEqual(xpGood, 15)
        XCTAssertEqual(good.masteryStage, 1)
        XCTAssertGreaterThan(good.stabilityDays, 1.0)

        // Wrong answer drops stability and increments lapses, and re-insert offset stays bounded.
        let (missed, xpMissed, _) = WordGameEngine.evaluateAnswer(
            existing: good,
            entryId: 1,
            isCorrect: false,
            usedHintOrNearMiss: false,
            responseMs: 6_000,
            wasRetriedInRound: false,
            now: now
        )
        XCTAssertEqual(xpMissed, 0)
        XCTAssertEqual(missed.lapses, 1)
        XCTAssertLessThan(missed.stabilityDays, good.stabilityDays)
        XCTAssertEqual(WordGameEngine.reinsertIndex(remainingCount: 5), 3)
        XCTAssertEqual(WordGameEngine.reinsertIndex(remainingCount: 1), 1)

        // Tajik letter folding near-miss detection.
        XCTAssertEqual(WordGameEngine.checkTypedAnswer(input: "хӯрдан", target: "хӯрдан"), .exact)
        XCTAssertEqual(WordGameEngine.checkTypedAnswer(input: "хурдан", target: "хӯрдан"), .tajikLetterNearMiss(target: "хӯрдан"))
        XCTAssertEqual(WordGameEngine.checkTypedAnswer(input: "китоб", target: "хӯрдан"), .wrong)
    }

    func testWordGameClozeAndSummaryStreak() {
        let cloze = WordGameEngine.makeClozeSentence(exampleTg: "Салом, дӯстам!", targetHeadword: "салом")
        XCTAssertEqual(cloze, "____, дӯстам!")

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = Date(timeIntervalSince1970: 1_731_628_800) // 2024-11-15
        let yesterday = today.addingTimeInterval(-WordGameEngine.daySeconds)

        let logs = [
            DailyStudySnapshot(dateKey: WordGameEngine.dateKey(for: yesterday, calendar: cal), wordsReviewed: 10, wordsLearned: 4, xpEarned: 110, roundsCompleted: 1),
            DailyStudySnapshot(dateKey: WordGameEngine.dateKey(for: today, calendar: cal), wordsReviewed: 5, wordsLearned: 2, xpEarned: 60, roundsCompleted: 0),
        ]
        let summary = WordGameEngine.computeSummary(
            progress: [
                WordProgressSnapshot(entryId: 1, masteryStage: 4, stabilityDays: 14, lastReviewedAt: today, nextReviewAt: today.addingTimeInterval(14 * WordGameEngine.daySeconds)),
            ],
            logs: logs,
            dailyGoal: 10,
            now: today,
            calendar: cal
        )
        XCTAssertEqual(summary.currentStreakDays, 2)
        XCTAssertEqual(summary.totalXp, 170)
        XCTAssertEqual(summary.level, 2)
        XCTAssertEqual(summary.masteredCount, 1)
    }

    func testZipfTextCoveragePlacementAndStudyAnalytics() {
        XCTAssertEqual(WordGameEngine.textRecognitionPercent(effectiveKnownWords: 0), 0)
        let pct100 = WordGameEngine.textRecognitionPercent(effectiveKnownWords: 100)
        let pct500 = WordGameEngine.textRecognitionPercent(effectiveKnownWords: 500)
        let pct2000 = WordGameEngine.textRecognitionPercent(effectiveKnownWords: 2000)
        XCTAssertTrue(pct100 > 25 && pct100 < 40)
        XCTAssertTrue(pct500 > pct100 && pct500 < pct2000)
        XCTAssertTrue(pct2000 > 80)

        let tier1 = WordCardCandidate(entryId: 10, language: .tajik, headword: "салом", preview: "hello", pos: .interjection, frequency: 95, topic: nil, exampleTg: nil, examplePartner: nil)
        let tier2 = WordCardCandidate(entryId: 11, language: .tajik, headword: "китоб", preview: "book", pos: .noun, frequency: 84, topic: nil, exampleTg: nil, examplePartner: nil)
        let tier3 = WordCardCandidate(entryId: 12, language: .tajik, headword: "андеша", preview: "thought", pos: .noun, frequency: 74, topic: nil, exampleTg: nil, examplePartner: nil)
        let tier4 = WordCardCandidate(entryId: 13, language: .tajik, headword: "камолот", preview: "perfection", pos: .noun, frequency: 52, topic: nil, exampleTg: nil, examplePartner: nil)

        let answers = [
            PlacementAnswer(question: PlacementQuestion(candidate: tier1, tier: 1, choices: []), isCorrect: true),
            PlacementAnswer(question: PlacementQuestion(candidate: tier2, tier: 2, choices: []), isCorrect: true),
            PlacementAnswer(question: PlacementQuestion(candidate: tier3, tier: 3, choices: []), isCorrect: false),
            PlacementAnswer(question: PlacementQuestion(candidate: tier4, tier: 4, choices: []), isCorrect: false),
        ]
        let placement = WordGameEngine.evaluatePlacement(answers: answers)
        XCTAssertEqual(placement.cefrLevel, .a2)
        XCTAssertEqual(placement.knownEntryIds, [10, 11])
        XCTAssertEqual(placement.focusEntryIds, [12, 13])

        XCTAssertEqual(WordGameEngine.formatStudyDuration(seconds: 45), "45s")
        XCTAssertEqual(WordGameEngine.formatStudyDuration(seconds: 1800), "30m")
        XCTAssertEqual(WordGameEngine.formatStudyDuration(seconds: 5400), "1h 30m")

        // Frontier queue prioritizes words <= targetMaxFrequency (e.g. 82 for A2).
        let queue = WordGameEngine.buildRoundQueue(
            candidates: [tier1, tier2, tier3, tier4],
            progressById: [:],
            roundSize: 2,
            targetMaxFrequency: 82
        )
        XCTAssertEqual(queue.map(\.entryId), [12, 13])

        // Whole-word cloze matching must not match short targets inside longer words.
        XCTAssertNil(WordGameEngine.makeClozeSentence(exampleTg: "Китобхона калон аст.", targetHeadword: "он"))
        XCTAssertEqual(WordGameEngine.makeClozeSentence(exampleTg: "Он китоб хуб аст.", targetHeadword: "он"), "____ китоб хуб аст.")

        // Due & weak decks filter properly.
        let now = Date(timeIntervalSince1970: 1_731_000_000)
        let weakSnapshot = WordProgressSnapshot(
            entryId: 12,
            masteryStage: 1,
            stabilityDays: 0.5,
            repetitions: 2,
            lapses: 2,
            lastReviewedAt: now.addingTimeInterval(-WordGameEngine.daySeconds),
            nextReviewAt: now.addingTimeInterval(-100),
            isKnownSkipped: false
        )
        let dueOnly = WordGameEngine.buildDueRoundQueue(candidates: [tier1, tier2, tier3, tier4], progressById: [12: weakSnapshot], now: now)
        XCTAssertEqual(dueOnly.map(\.entryId), [12])
        let weakOnly = WordGameEngine.buildWeakRoundQueue(candidates: [tier1, tier2, tier3, tier4], progressById: [12: weakSnapshot])
        XCTAssertEqual(weakOnly.map(\.entryId), [12])

        // Classic flashcard grading advances masteryStage & XP.
        let classicEval = WordGameEngine.evaluateClassicFlashcard(
            existing: nil,
            entryId: 10,
            rating: .good,
            intervalDays: 1,
            nextDue: now.addingTimeInterval(WordGameEngine.daySeconds),
            now: now
        )
        XCTAssertEqual(classicEval.updated.masteryStage, 1)
        XCTAssertTrue(classicEval.newlyLearned)
        XCTAssertEqual(classicEval.xpAwarded, 8)
    }

    func testFullBackupV2RoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1_731_000_000)
        let fav = FavoriteItem(entryId: 1, lang: "tg", headword: "китоб", preview: "книга", addedAt: now)
        let card = FlashcardProgress(entryId: 1, lang: "tg", headword: "китоб", preview: "книга", repetitions: 2, intervalDays: 6, easeFactor: 2.5, nextReviewAt: now, masteryStage: 2, stabilityDays: 6.0, lapses: 0, lastReviewedAt: now, isKnownSkipped: false)
        let log = DailyStudyLog(dateKey: "2026-11-15", wordsReviewed: 5, wordsLearned: 2, xpEarned: 55, roundsCompleted: 1, studySeconds: 90, correctReviews: 4)
        let placement = FavoritesBackup.PlacementRecord(cefrLevel: "A2", ceilingFreq: 82, baselineWords: 500)

        let data = try FavoritesBackup.encodeFull(favorites: [fav], flashcards: [card], dailyLogs: [log], placement: placement, exportedAt: now)
        let decoded = try FavoritesBackup.decodeFull(from: data)
        XCTAssertEqual(decoded.favorites.count, 1)
        XCTAssertEqual(decoded.flashcards.count, 1)
        XCTAssertEqual(decoded.flashcards.first?.masteryStage, 2)
        XCTAssertEqual(decoded.dailyLogs.first?.studySeconds, 90)
        XCTAssertEqual(decoded.placement?.cefrLevel, "A2")
    }

    func testTransliteratorAndDetailSensesHomographsSynonyms() async throws {
        XCTAssertEqual(TajikTransliterator.toLatin("Салом"), "salom")
        XCTAssertEqual(TajikTransliterator.toLatin("соҳибӣ"), "sohibī")
        XCTAssertEqual(TajikTransliterator.toLatin("хӯрдан"), "khūrdan")
        XCTAssertEqual(TajikTransliterator.toLatin("мекунам"), "mekunam")

        let repo = try DictionaryRepository()
        let outcome = try await repo.search(query: "соҳибӣ", mode: .tjRu)
        let nounHit = try XCTUnwrap(outcome.results.first { $0.headword == "соҳибӣ" && $0.pos == .noun })
        let loadedDetail = try await repo.detail(id: nounHit.id, mode: .tjRu)
        let detail = try XCTUnwrap(loadedDetail)

        XCTAssertFalse(detail.homographs.isEmpty)
        XCTAssertTrue(detail.homographs.contains { $0.pos == .adjective })
        XCTAssertFalse(detail.synonyms.isEmpty)
        XCTAssertFalse(detail.relatedWords.isEmpty)

        let ruTranslations = detail.translations[.russian] ?? []
        XCTAssertTrue(Set(ruTranslations.map(\.position)).count >= 2)
    }
}
