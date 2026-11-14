import Foundation

/// Rule-based stemmer and bounded Levenshtein edit distance for offline fallback search.
/// Operates on normalized `searchKey` strings from `TextNormalizer`.
enum WordStemmer {
    private static let tajikPrefixes = ["ме", "на", "би", "бе", "бо", "хам"]
    private static let tajikSuffixes = [
        "амон", "атон", "ашон", "хо", "он", "ро", "ам", "ат", "аш",
        "ем", "ед", "анд", "и", "е",
    ]
    private static let tajikPresentToInfinitive: [String: String] = [
        "рав": "рафтан",
        "о": "омадан",
        "оя": "омадан",
        "бин": "дидан",
        "гу": "гуфтан",
        "гуй": "гуфтан",
        "кун": "кардан",
        "бош": "будан",
        "дор": "доштан",
        "навис": "навиштан",
        "омуз": "омухтан",
        "фуруш": "фурухтан",
        "дех": "додан",
        "гир": "гирифтан",
        "шин": "нишастан",
        "хез": "хестан",
    ]

    private static let russianSuffixes = [
        "ами", "ями", "ов", "ев", "ах", "ях", "ом", "ем", "ой", "ей", "ы", "и", "а", "у", "е",
    ]

    static func candidateStems(for key: String, languages: Set<Language>) -> [String] {
        guard key.count >= 3 else { return [] }
        var seen: Set<String> = [key]
        var stems: [String] = []

        func appendUnique(_ value: String) {
            if seen.insert(value).inserted {
                stems.append(value)
            }
        }

        if languages.contains(.tajik) {
            var bases = [key]
            for prefix in tajikPrefixes where key.hasPrefix(prefix) && key.count - prefix.count >= 2 {
                let after = String(key.dropFirst(prefix.count))
                bases.append(after)
                appendUnique(after)
            }
            for base in bases {
                for suffix in tajikSuffixes where base.hasSuffix(suffix) && base.count - suffix.count >= 2 {
                    let stripped = String(base.dropLast(suffix.count))
                    appendUnique(stripped)
                    if let inf = tajikPresentToInfinitive[stripped] {
                        appendUnique(inf)
                    }
                }
                if let inf = tajikPresentToInfinitive[base] {
                    appendUnique(inf)
                }
            }
        }

        if languages.contains(.russian), key.count >= 4 {
            for suffix in russianSuffixes where key.hasSuffix(suffix) && key.count - suffix.count >= 3 {
                appendUnique(String(key.dropLast(suffix.count)))
            }
        }

        if languages.contains(.english), key.count >= 4 {
            if key.hasSuffix("ies"), key.count > 4 {
                appendUnique(String(key.dropLast(3)) + "y")
            } else if key.hasSuffix("ing"), key.count > 5 {
                let base = String(key.dropLast(3))
                appendUnique(base)
                appendUnique(base + "e")
            } else if key.hasSuffix("ed"), key.count > 4 {
                let base = String(key.dropLast(2))
                appendUnique(base)
                appendUnique(base + "e")
            } else if key.hasSuffix("es"), key.count > 4 {
                appendUnique(String(key.dropLast(2)))
            } else if key.hasSuffix("s"), key.count > 3 {
                appendUnique(String(key.dropLast(1)))
            }
        }

        return stems
    }

    /// Bounded Levenshtein edit distance with early exit above `maxDistance`.
    static func editDistance(_ a: String, _ b: String, maxDistance: Int = 2) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if abs(aChars.count - bChars.count) > maxDistance { return maxDistance + 1 }
        if aChars == bChars { return 0 }

        var prev = Array(0...bChars.count)
        var curr = Array(repeating: 0, count: bChars.count + 1)
        for i in 1...aChars.count {
            curr[0] = i
            var rowMin = curr[0]
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(min(curr[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost)
                if curr[j] < rowMin { rowMin = curr[j] }
            }
            if rowMin > maxDistance { return maxDistance + 1 }
            swap(&prev, &curr)
        }
        return prev[bChars.count]
    }
}
