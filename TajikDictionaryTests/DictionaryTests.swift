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
}
