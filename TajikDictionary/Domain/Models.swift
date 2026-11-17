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
