import SwiftUI

/// A dictionary language matching `entries.lang` in `dictionary.sqlite`.
enum Language: String, CaseIterable, Codable, Hashable, Sendable {
    case tajik = "tg"
    case russian = "ru"
    case english = "en"

    var tag: String {
        switch self {
        case .tajik: return "TJ"
        case .russian: return "RU"
        case .english: return "EN"
        }
    }

    var displayName: String {
        switch self {
        case .tajik: return String(localized: "Tajik")
        case .russian: return String(localized: "Russian")
        case .english: return String(localized: "English")
        }
    }

    var speechLocaleIdentifier: String? {
        switch self {
        case .tajik: return nil
        case .russian: return "ru-RU"
        case .english: return "en-US"
        }
    }

    /// Consistent brand badge color adapted for light & dark mode.
    var tagColor: Color {
        switch self {
        case .tajik: return Color(light: Color(red: 0.031, green: 0.463, blue: 0.325), dark: Color(red: 0.435, green: 0.847, blue: 0.675))
        case .russian: return Color(light: Color(red: 0.141, green: 0.349, blue: 0.780), dark: Color(red: 0.54, green: 0.71, blue: 1.0))
        case .english: return Color(light: Color(red: 0.76, green: 0.25, blue: 0.05), dark: Color(red: 1.0, green: 0.64, blue: 0.42))
        }
    }
}

/// The two bidirectional dictionary modes. Each searches Tajik plus one partner language.
enum DictionaryMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case tjRu
    case tjEn

    var id: String { rawValue }

    var partner: Language {
        switch self {
        case .tjRu: return .russian
        case .tjEn: return .english
        }
    }

    var languages: Set<Language> {
        [.tajik, partner]
    }

    var title: String {
        switch self {
        case .tjRu: return "TJK ⇄ RUS"
        case .tjEn: return "TJK ⇄ ENG"
        }
    }

    func translationTarget(for language: Language) -> Language {
        language == .tajik ? partner : .tajik
    }
}

enum PartOfSpeech: String, CaseIterable, Sendable {
    case noun = "n"
    case verb = "v"
    case adjective = "adj"
    case adverb = "adv"
    case pronoun = "pron"
    case numeral = "num"
    case preposition = "prep"
    case conjunction = "conj"
    case interjection = "intj"
    case particle = "part"
    case phrase = "phr"

    var label: String {
        switch self {
        case .noun: return String(localized: "noun")
        case .verb: return String(localized: "verb")
        case .adjective: return String(localized: "adj.")
        case .adverb: return String(localized: "adv.")
        case .pronoun: return String(localized: "pron.")
        case .numeral: return String(localized: "num.")
        case .preposition: return String(localized: "prep.")
        case .conjunction: return String(localized: "conj.")
        case .interjection: return String(localized: "interj.")
        case .particle: return String(localized: "part.")
        case .phrase: return String(localized: "phrase")
        }
    }
}

private extension Color {
    init(light: Color, dark: Color) {
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
