import Foundation

/// Deterministic Cyrillic-to-Latin pronunciation guide for Tajik words and example sentences.
enum TajikTransliterator {
    private static let vowelOrBoundary: Set<Character> = [
        "а", "е", "ё", "и", "ӣ", "о", "у", "ӯ", "э", "ю", "я", "ъ", "ь",
    ]

    static func toLatin(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let scalars = Array(trimmed.lowercased())
        var out = String()
        out.reserveCapacity(scalars.count + 8)

        for i in scalars.indices {
            let ch = scalars[i]
            let prev: Character = i > 0 ? scalars[i - 1] : " "
            let atWordStart = i == 0 || !prev.isLetter
            switch ch {
            case "а": out.append("a")
            case "б": out.append("b")
            case "в": out.append("v")
            case "г": out.append("g")
            case "ғ": out.append("gh")
            case "д": out.append("d")
            case "е": out.append((atWordStart || vowelOrBoundary.contains(prev)) ? "ye" : "e")
            case "ё": out.append("yo")
            case "ж": out.append("zh")
            case "з": out.append("z")
            case "и": out.append("i")
            case "ӣ": out.append("ī")
            case "й": out.append("y")
            case "к": out.append("k")
            case "қ": out.append("q")
            case "л": out.append("l")
            case "м": out.append("m")
            case "н": out.append("n")
            case "о": out.append("o")
            case "п": out.append("p")
            case "р": out.append("r")
            case "с": out.append("s")
            case "т": out.append("t")
            case "у": out.append("u")
            case "ӯ": out.append("ū")
            case "ф": out.append("f")
            case "х": out.append("kh")
            case "ҳ": out.append("h")
            case "ч": out.append("ch")
            case "ҷ": out.append("j")
            case "ш": out.append("sh")
            case "ъ": out.append("’")
            case "ы": out.append("i")
            case "ь": break
            case "э": out.append("e")
            case "ю": out.append("yu")
            case "я": out.append("ya")
            case "ц": out.append("ts")
            case "щ": out.append("shch")
            default: out.append(ch)
            }
        }
        return out
    }
}
