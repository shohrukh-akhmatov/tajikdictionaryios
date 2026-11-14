import Foundation

struct SearchResult: Identifiable, Hashable, Sendable {
    let id: Int64
    let language: Language
    let headword: String
    let pos: PartOfSpeech?
    let preview: String
}

struct SearchOutcome: Sendable {
    let query: String
    let results: [SearchResult]
    let searchedLanguages: Set<Language>
    let suggestedMode: DictionaryMode?

    static let empty = SearchOutcome(query: "", results: [], searchedLanguages: [], suggestedMode: nil)
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
    var id: Int64 { entryId }
    let entryId: Int64
    let language: Language
    let headword: String
    let pos: PartOfSpeech?
    let note: String?
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
}

struct DictionaryInfo: Sendable {
    let dataVersion: String
    let stats: String
}
