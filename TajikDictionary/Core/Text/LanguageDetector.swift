import Foundation

/// Guesses which dictionary languages a raw query can belong to (`docs/DATA_AND_SEARCH.md` §4.1).
/// Rules are evaluated in order; the first match wins.
enum LanguageDetector {
    private static let tajikOnly: Set<Character> = ["ғ", "ӣ", "қ", "ӯ", "ҳ", "ҷ"]
    private static let russianOnly: Set<Character> = ["ц", "щ", "ы", "ь"]

    static func candidates(for rawQuery: String) -> Set<Language> {
        let lowered = rawQuery.lowercased()
        if lowered.contains(where: { $0 >= "a" && $0 <= "z" }) {
            return [.english]
        }
        if lowered.contains(where: { tajikOnly.contains($0) }) {
            return [.tajik]
        }
        if lowered.contains(where: { russianOnly.contains($0) }) {
            return [.russian]
        }
        if lowered.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) || (0x0500...0x052F).contains($0.value) }) {
            return [.tajik, .russian]
        }
        return Set(Language.allCases)
    }
}
