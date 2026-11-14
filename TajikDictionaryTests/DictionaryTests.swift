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
}
