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

/// SM-2 flashcard review state persisted separately from the read-only dictionary DB.
@Model
final class FlashcardProgress {
    @Attribute(.unique) var entryId: Int64
    var lang: String
    var headword: String
    var preview: String
    var repetitions: Int
    var intervalDays: Int
    var easeFactor: Double
    var nextReviewAt: Date

    init(
        entryId: Int64,
        lang: String,
        headword: String,
        preview: String,
        repetitions: Int = 0,
        intervalDays: Int = 0,
        easeFactor: Double = 2.5,
        nextReviewAt: Date = .now
    ) {
        self.entryId = entryId
        self.lang = lang
        self.headword = headword
        self.preview = preview
        self.repetitions = repetitions
        self.intervalDays = intervalDays
        self.easeFactor = easeFactor
        self.nextReviewAt = nextReviewAt
    }
}
