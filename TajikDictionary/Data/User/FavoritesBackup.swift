import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Portable JSON backup format (v1 favorites-only & v2 full learning backup) shared across Android and iOS.
enum FavoritesBackup {
    static let currentVersion = 2

    struct Record: Codable, Equatable, Sendable {
        let entryId: Int64
        let lang: String
        let headword: String
        let preview: String
        let addedAt: Int64
    }

    struct FlashcardRecord: Codable, Equatable, Sendable {
        let entryId: Int64
        let lang: String
        let headword: String
        let preview: String
        let repetitions: Int
        let intervalDays: Int
        let easeFactor: Double
        let nextReviewAt: Int64
        let masteryStage: Int
        let stabilityDays: Double
        let lapses: Int
        let lastReviewedAt: Int64?
        let isKnownSkipped: Bool
    }

    struct DailyLogRecord: Codable, Equatable, Sendable {
        let dateKey: String
        let wordsReviewed: Int
        let wordsLearned: Int
        let xpEarned: Int
        let roundsCompleted: Int
        let studySeconds: Int
        let correctReviews: Int
    }

    struct PlacementRecord: Codable, Equatable, Sendable {
        let cefrLevel: String
        let ceilingFreq: Int
        let baselineWords: Int
    }

    struct Payload: Codable, Equatable, Sendable {
        let version: Int
        let exportedAt: Int64
        let favorites: [Record]
        let flashcards: [FlashcardRecord]?
        let dailyLogs: [DailyLogRecord]?
        let placement: PlacementRecord?
    }

    struct FullBackupData: Equatable, Sendable {
        let favorites: [Record]
        let flashcards: [FlashcardRecord]
        let dailyLogs: [DailyLogRecord]
        let placement: PlacementRecord?
    }

    static func encode(_ items: [FavoriteItem], exportedAt: Date = .now) throws -> Data {
        let records = items.map { item in
            Record(
                entryId: item.entryId,
                lang: item.lang,
                headword: item.headword,
                preview: item.preview,
                addedAt: Int64(item.addedAt.timeIntervalSince1970 * 1000)
            )
        }
        return try encodeRecords(records, exportedAtMs: Int64(exportedAt.timeIntervalSince1970 * 1000))
    }

    static func encodeFull(
        favorites: [FavoriteItem],
        flashcards: [FlashcardProgress],
        dailyLogs: [DailyStudyLog],
        placement: PlacementRecord?,
        exportedAt: Date = .now
    ) throws -> Data {
        let favRecords = favorites.map { item in
            Record(
                entryId: item.entryId,
                lang: item.lang,
                headword: item.headword,
                preview: item.preview,
                addedAt: Int64(item.addedAt.timeIntervalSince1970 * 1000)
            )
        }
        let cardRecords = flashcards.map { item in
            FlashcardRecord(
                entryId: item.entryId,
                lang: item.lang,
                headword: item.headword,
                preview: item.preview,
                repetitions: item.repetitions,
                intervalDays: item.intervalDays,
                easeFactor: item.easeFactor,
                nextReviewAt: Int64(item.nextReviewAt.timeIntervalSince1970 * 1000),
                masteryStage: item.masteryStage,
                stabilityDays: item.stabilityDays,
                lapses: item.lapses,
                lastReviewedAt: item.lastReviewedAt.map { Int64($0.timeIntervalSince1970 * 1000) },
                isKnownSkipped: item.isKnownSkipped
            )
        }
        let logRecords = dailyLogs.map { item in
            DailyLogRecord(
                dateKey: item.dateKey,
                wordsReviewed: item.wordsReviewed,
                wordsLearned: item.wordsLearned,
                xpEarned: item.xpEarned,
                roundsCompleted: item.roundsCompleted,
                studySeconds: item.studySeconds,
                correctReviews: item.correctReviews
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(
            Payload(
                version: currentVersion,
                exportedAt: Int64(exportedAt.timeIntervalSince1970 * 1000),
                favorites: favRecords,
                flashcards: cardRecords,
                dailyLogs: logRecords,
                placement: placement
            )
        )
    }

    static func encodeRecords(_ records: [Record], exportedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(
            Payload(version: 1, exportedAt: exportedAtMs, favorites: records, flashcards: nil, dailyLogs: nil, placement: nil)
        )
    }

    static func decodeRecords(from data: Data) throws -> [Record] {
        try decodeFull(from: data).favorites
    }

    static func decodeFull(from data: Data) throws -> FullBackupData {
        let decoder = JSONDecoder()
        if let payload = try? decoder.decode(Payload.self, from: data) {
            return FullBackupData(
                favorites: payload.favorites.filter { !$0.lang.isEmpty && !$0.headword.isEmpty },
                flashcards: (payload.flashcards ?? []).filter { !$0.lang.isEmpty && !$0.headword.isEmpty },
                dailyLogs: (payload.dailyLogs ?? []).filter { !$0.dateKey.isEmpty },
                placement: payload.placement
            )
        }
        let rawList = try decoder.decode([Record].self, from: data)
        return FullBackupData(
            favorites: rawList.filter { !$0.lang.isEmpty && !$0.headword.isEmpty },
            flashcards: [],
            dailyLogs: [],
            placement: nil
        )
    }
}

struct FavoritesBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
