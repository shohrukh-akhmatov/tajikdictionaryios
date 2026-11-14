import Foundation

/// Search normalization shared by Android, iOS, and Python build tools.
/// Must stay identical to `docs/DATA_AND_SEARCH.md` §3.
enum TextNormalizer {
    private static let breveScalar: UnicodeScalar = "\u{0306}"
    private static let foldMap: [UnicodeScalar: UnicodeScalar] = [
        "ғ": "г",
        "қ": "к",
        "ҳ": "х",
        "ҷ": "ч",
    ]
    private static let apostropheScalars: Set<UnicodeScalar> = [
        "'", "\u{2018}", "\u{2019}", "\u{02BC}", "`",
    ]

    /// Normalizes a query or headword: `"Ҳафта" -> "хафта"`, `"хӯрдан" -> "хурдан"`, `"Don't" -> "dont"`.
    static func normalize(_ text: String) -> String {
        let decomposed = text.lowercased().decomposedStringWithCanonicalMapping
        var filtered = String.UnicodeScalarView()
        filtered.reserveCapacity(decomposed.unicodeScalars.count)

        for scalar in decomposed.unicodeScalars {
            let isNonSpacingMark = scalar.properties.generalCategory == .nonspacingMark
            if !isNonSpacingMark || scalar == breveScalar {
                filtered.append(foldMap[scalar] ?? scalar)
            }
        }

        let composed = String(filtered).precomposedStringWithCanonicalMapping
        var cleaned = String.UnicodeScalarView()
        cleaned.reserveCapacity(composed.unicodeScalars.count)

        var lastWasSpace = true
        for scalar in composed.unicodeScalars {
            if apostropheScalars.contains(scalar) {
                continue
            }
            if CharacterSet.alphanumerics.contains(scalar) {
                cleaned.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                cleaned.append(" ")
                lastWasSpace = true
            }
        }

        var result = String(cleaned)
        while result.last == " " {
            result.removeLast()
        }
        return result
    }

    /// `normalize(_:)` plus dropping the English infinitive `"to "` prefix (`"to go" -> "go"`).
    static func searchKey(_ text: String) -> String {
        let s = normalize(text)
        if s.hasPrefix("to "), s.count > 3 {
            return String(s.dropFirst(3))
        }
        return s
    }
}
