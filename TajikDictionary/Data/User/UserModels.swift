import Foundation
import SwiftData

/// Saved/favorite word persisted separately from the read-only dictionary DB.
@Model
final class FavoriteItem {
    @Attribute(.unique) var entryId: Int64
    var lang: String
    var headword: String
    var preview: String
    var addedAt: Date

    init(entryId: Int64, lang: String, headword: String, preview: String, addedAt: Date = .now) {
        self.entryId = entryId
        self.lang = lang
        self.headword = headword
        self.preview = preview
        self.addedAt = addedAt
    }

    var language: Language { Language(rawValue: lang) ?? .tajik }
}

/// Recent lookup persisted separately from the read-only dictionary DB (capped at 200 items).
@Model
final class HistoryItem {
    @Attribute(.unique) var entryId: Int64
    var lang: String
    var headword: String
    var preview: String
    var viewedAt: Date

    init(entryId: Int64, lang: String, headword: String, preview: String, viewedAt: Date = .now) {
        self.entryId = entryId
        self.lang = lang
        self.headword = headword
        self.preview = preview
        self.viewedAt = viewedAt
    }

    var language: Language { Language(rawValue: lang) ?? .tajik }

    static let maxItems = 200
}
