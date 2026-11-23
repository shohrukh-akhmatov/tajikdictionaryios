import Foundation

struct SearchResult: Identifiable, Hashable, Sendable {
    let id: Int64
    let language: Language
    let headword: String
    let pos: PartOfSpeech?
    let preview: String
}

enum SearchMatchType: Sendable {
    case direct
    case stem
    case fuzzy
    /// The full phrase isn't in the dictionary; results are lookups of its individual words, in query order.
    case words
}

struct SearchOutcome: Sendable {
    let query: String
    let results: [SearchResult]
    let searchedLanguages: Set<Language>
    let suggestedMode: DictionaryMode?
    let matchType: SearchMatchType

    init(
        query: String,
        results: [SearchResult],
        searchedLanguages: Set<Language>,
        suggestedMode: DictionaryMode?,
        matchType: SearchMatchType = .direct
    ) {
        self.query = query
        self.results = results
        self.searchedLanguages = searchedLanguages
        self.suggestedMode = suggestedMode
        self.matchType = matchType
    }

    static let empty = SearchOutcome(query: "", results: [], searchedLanguages: [], suggestedMode: nil)
}

struct TopicCount: Identifiable, Hashable, Sendable {
    var id: String { topic }
    let topic: String
    let count: Int
}

struct Entry: Identifiable, Hashable, Sendable {
    let id: Int64
    let language: Language
    let headword: String
    let pos: PartOfSpeech?
    let frequency: Int
    let topic: String?
}

struct Translation: Identifiable, Hashable, Sendable {
    var id: String { "\(entryId)_\(position)" }
    let entryId: Int64
    let language: Language
    let headword: String
    let pos: PartOfSpeech?
    let note: String?
    let position: Int
}

struct Example: Identifiable, Hashable, Sendable {
    let id: Int
    let tg: String
    let ru: String?
    let en: String?
}

struct EntryDetail: Sendable {
    let entry: Entry
    let translations: [Language: [Translation]]
    let examples: [Example]
    let homographs: [SearchResult]
    let synonyms: [SearchResult]
    let relatedWords: [SearchResult]

    init(
        entry: Entry,
        translations: [Language: [Translation]],
        examples: [Example],
        homographs: [SearchResult] = [],
        synonyms: [SearchResult] = [],
        relatedWords: [SearchResult] = []
    ) {
        self.entry = entry
        self.translations = translations
        self.examples = examples
        self.homographs = homographs
        self.synonyms = synonyms
        self.relatedWords = relatedWords
    }
}

struct DictionaryInfo: Sendable {
    let dataVersion: String
    let stats: String
}

enum ProfileKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case adult = "adult"
    case child = "child"

    var id: String { rawValue }

    var defaultDailyGoal: Int {
        switch self {
        case .adult: return 10
        case .child: return 5
        }
    }

    var roundSize: Int {
        switch self {
        case .adult: return 10
        case .child: return 6
        }
    }

    static func fromCode(_ raw: String?) -> ProfileKind {
        guard let raw = raw?.lowercased() else { return .adult }
        return ProfileKind(rawValue: raw) ?? .adult
    }
}

/// Local learner profile on the device. Each profile has an isolated SwiftData learning store and learning settings.
/// Limited to `maxProfiles` (3) per device so local storage and iCloud/Google backups remain compact.
struct LearnerProfile: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var name: String
    var avatar: String
    var colorHex: String
    var kind: ProfileKind
    var createdAtMs: Int64

    var isChild: Bool { kind == .child }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case avatar
        case colorHex = "color"
        case kind
        case createdAtMs = "createdAt"
    }

    init(
        id: String,
        name: String,
        avatar: String,
        colorHex: String,
        kind: ProfileKind = .adult,
        createdAtMs: Int64 = 0
    ) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.colorHex = colorHex
        self.kind = kind
        self.createdAtMs = createdAtMs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? Self.defaultProfileId
        self.name = (try? c.decode(String.self, forKey: .name)) ?? Self.defaultName
        self.avatar = (try? c.decode(String.self, forKey: .avatar)) ?? Self.defaultAvatar
        self.colorHex = (try? c.decode(String.self, forKey: .colorHex)) ?? Self.defaultColor
        let kindRaw = try? c.decode(String.self, forKey: .kind)
        self.kind = ProfileKind.fromCode(kindRaw)
        self.createdAtMs = (try? c.decode(Int64.self, forKey: .createdAtMs)) ?? 0
    }

    static let maxProfiles = 3
    static let defaultProfileId = "default"
    static let defaultName = "Me"
    static let defaultAvatar = "🦊"
    static let defaultColor = "#087653"
    static let whoIsLearningCooldownSeconds: TimeInterval = 10 * 60

    static let avatars: [String] = ["🦊", "🦁", "🐼", "🦉", "🐯", "🦋", "🚀", "🌟", "📚", "🏔️", "🎨", "⚽"]
    static let colors: [String] = ["#087653", "#1E6F9F", "#7B1FA2", "#E65100", "#C62828", "#2E7D32"]

    static func defaultProfile(name: String = defaultName, createdAtMs: Int64 = 0) -> LearnerProfile {
        LearnerProfile(
            id: defaultProfileId,
            name: name,
            avatar: defaultAvatar,
            colorHex: defaultColor,
            kind: .adult,
            createdAtMs: createdAtMs
        )
    }
}

/// Lightweight summary of a profile's learning progress for the Family Board & Profile Switcher.
struct ProfileStatsSnapshot: Codable, Equatable, Sendable {
    var profileId: String
    var currentStreakDays: Int = 0
    var longestStreakDays: Int = 0
    var totalXp: Int = 0
    var masteredCount: Int = 0
    var knownWordsCount: Int = 0
    var todayReviewed: Int = 0
    var dailyGoal: Int = 10
    var cefrCode: String = "A0"
    var lastActiveDateKey: String? = nil

    func practicedToday(todayDateKey: String) -> Bool {
        lastActiveDateKey == todayDateKey && todayReviewed > 0
    }
}
