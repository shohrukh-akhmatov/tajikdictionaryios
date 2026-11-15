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

/// SM-2 & Lingvist-style periodic flashcard review state persisted separately from the read-only dictionary DB.
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
    var masteryStage: Int = 0
    var stabilityDays: Double = 0
    var lapses: Int = 0
    var lastReviewedAt: Date? = nil
    var isKnownSkipped: Bool = false

    init(
        entryId: Int64,
        lang: String,
        headword: String,
        preview: String,
        repetitions: Int = 0,
        intervalDays: Int = 0,
        easeFactor: Double = 2.5,
        nextReviewAt: Date = .now,
        masteryStage: Int = 0,
        stabilityDays: Double = 0,
        lapses: Int = 0,
        lastReviewedAt: Date? = nil,
        isKnownSkipped: Bool = false
    ) {
        self.entryId = entryId
        self.lang = lang
        self.headword = headword
        self.preview = preview
        self.repetitions = repetitions
        self.intervalDays = intervalDays
        self.easeFactor = easeFactor
        self.nextReviewAt = nextReviewAt
        self.masteryStage = masteryStage
        self.stabilityDays = stabilityDays
        self.lapses = lapses
        self.lastReviewedAt = lastReviewedAt
        self.isKnownSkipped = isKnownSkipped
    }

    var snapshot: WordProgressSnapshot {
        WordProgressSnapshot(
            entryId: entryId,
            masteryStage: masteryStage,
            stabilityDays: stabilityDays,
            repetitions: repetitions,
            lapses: lapses,
            lastReviewedAt: lastReviewedAt,
            nextReviewAt: nextReviewAt,
            isKnownSkipped: isKnownSkipped
        )
    }
}

/// Daily study activity log for streaks, daily goals, study time, and XP progression.
@Model
final class DailyStudyLog {
    @Attribute(.unique) var dateKey: String
    var wordsReviewed: Int
    var wordsLearned: Int
    var xpEarned: Int
    var roundsCompleted: Int
    var studySeconds: Int = 0
    var correctReviews: Int = 0

    init(
        dateKey: String,
        wordsReviewed: Int = 0,
        wordsLearned: Int = 0,
        xpEarned: Int = 0,
        roundsCompleted: Int = 0,
        studySeconds: Int = 0,
        correctReviews: Int = 0
    ) {
        self.dateKey = dateKey
        self.wordsReviewed = wordsReviewed
        self.wordsLearned = wordsLearned
        self.xpEarned = xpEarned
        self.roundsCompleted = roundsCompleted
        self.studySeconds = studySeconds
        self.correctReviews = correctReviews
    }

    var snapshot: DailyStudySnapshot {
        DailyStudySnapshot(
            dateKey: dateKey,
            wordsReviewed: wordsReviewed,
            wordsLearned: wordsLearned,
            xpEarned: xpEarned,
            roundsCompleted: roundsCompleted,
            studySeconds: studySeconds,
            correctReviews: correctReviews
        )
    }
}
