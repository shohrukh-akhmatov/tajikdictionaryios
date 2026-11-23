import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Portable JSON backup format (v1 favorites-only, v2 full learning backup, and
/// cross-platform multi-user `ProfileBackup v1`) shared across Android and iOS.
enum FavoritesBackup {
    static let currentVersion = 2
    static let profileBackupFormat = "tajikdictionary.profile-backup"
    static let profileBackupVersion = 1

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

    struct ProfileSettingsBackup: Codable, Equatable, Sendable {
        var studyMode: String = DictionaryMode.tjEn.rawValue
        var dailyGoal: Int = 10
        var placementLevel: String? = nil
        var placementCeilingFreq: Int = 100
        var placementBaselineWords: Int = 0

        init(
            studyMode: String = DictionaryMode.tjEn.rawValue,
            dailyGoal: Int = 10,
            placementLevel: String? = nil,
            placementCeilingFreq: Int = 100,
            placementBaselineWords: Int = 0
        ) {
            self.studyMode = studyMode
            self.dailyGoal = dailyGoal
            self.placementLevel = placementLevel
            self.placementCeilingFreq = placementCeilingFreq
            self.placementBaselineWords = placementBaselineWords
        }
    }

    struct AppMetaRecord: Codable, Equatable, Sendable {
        let platform: String
        let version: String
    }

    struct ProfileEntryBackup: Codable, Equatable, Sendable {
        let profile: LearnerProfile
        let settings: ProfileSettingsBackup
        let favorites: [Record]
        let flashcards: [FlashcardRecord]
        let dailyLogs: [DailyLogRecord]

        enum CodingKeys: String, CodingKey {
            case profile
            case settings
            case favorites
            case progress
            case flashcards
            case dailyLogs
        }

        init(
            profile: LearnerProfile,
            settings: ProfileSettingsBackup,
            favorites: [Record],
            flashcards: [FlashcardRecord],
            dailyLogs: [DailyLogRecord]
        ) {
            self.profile = profile
            self.settings = settings
            self.favorites = favorites
            self.flashcards = flashcards
            self.dailyLogs = dailyLogs
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.profile = (try? c.decode(LearnerProfile.self, forKey: .profile)) ?? LearnerProfile.defaultProfile()
            self.settings = (try? c.decode(ProfileSettingsBackup.self, forKey: .settings))
                ?? ProfileSettingsBackup(dailyGoal: self.profile.kind.defaultDailyGoal)
            self.favorites = ((try? c.decode([Record].self, forKey: .favorites)) ?? [])
                .filter { !$0.lang.isEmpty && !$0.headword.isEmpty }
            let cards = (try? c.decode([FlashcardRecord].self, forKey: .progress))
                ?? (try? c.decode([FlashcardRecord].self, forKey: .flashcards))
                ?? []
            self.flashcards = cards.filter { !$0.lang.isEmpty && !$0.headword.isEmpty }
            self.dailyLogs = ((try? c.decode([DailyLogRecord].self, forKey: .dailyLogs)) ?? [])
                .filter { !$0.dateKey.isEmpty }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(profile, forKey: .profile)
            try c.encode(settings, forKey: .settings)
            try c.encode(favorites, forKey: .favorites)
            try c.encode(flashcards, forKey: .progress)
            try c.encode(dailyLogs, forKey: .dailyLogs)
        }
    }

    struct MultiProfilePayload: Codable, Equatable, Sendable {
        let format: String
        let version: Int
        let exportedAt: Int64
        let activeProfileId: String?
        let app: AppMetaRecord?
        let profiles: [ProfileEntryBackup]
    }

    static func encodeProfiles(
        profiles: [ProfileEntryBackup],
        activeProfileId: String,
        platform: String = "ios",
        appVersion: String = "1.0",
        exportedAt: Date = .now
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(
            MultiProfilePayload(
                format: profileBackupFormat,
                version: profileBackupVersion,
                exportedAt: Int64(exportedAt.timeIntervalSince1970 * 1000),
                activeProfileId: activeProfileId,
                app: AppMetaRecord(platform: platform, version: appVersion),
                profiles: profiles
            )
        )
    }

    static func decodeProfiles(from data: Data) throws -> MultiProfilePayload {
        let decoder = JSONDecoder()
        if let multi = try? decoder.decode(MultiProfilePayload.self, from: data), !multi.profiles.isEmpty {
            let resolvedActive = multi.activeProfileId.flatMap { id in
                multi.profiles.contains(where: { $0.profile.id == id }) ? id : nil
            } ?? multi.profiles.first?.profile.id ?? LearnerProfile.defaultProfileId
            return MultiProfilePayload(
                format: multi.format,
                version: multi.version,
                exportedAt: multi.exportedAt,
                activeProfileId: resolvedActive,
                app: multi.app,
                profiles: multi.profiles
            )
        }
        // Fallback: legacy single-profile backup (v1 or v2)
        let legacy = try decodeFull(from: data)
        let defProfile = LearnerProfile.defaultProfile()
        let settings = ProfileSettingsBackup(
            studyMode: DictionaryMode.tjEn.rawValue,
            dailyGoal: 10,
            placementLevel: legacy.placement?.cefrLevel,
            placementCeilingFreq: legacy.placement?.ceilingFreq ?? 100,
            placementBaselineWords: legacy.placement?.baselineWords ?? 0
        )
        return MultiProfilePayload(
            format: profileBackupFormat,
            version: profileBackupVersion,
            exportedAt: Int64(Date().timeIntervalSince1970 * 1000),
            activeProfileId: defProfile.id,
            app: nil,
            profiles: [
                ProfileEntryBackup(
                    profile: defProfile,
                    settings: settings,
                    favorites: legacy.favorites,
                    flashcards: legacy.flashcards,
                    dailyLogs: legacy.dailyLogs
                )
            ]
        )
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
        if let multi = try? decoder.decode(MultiProfilePayload.self, from: data), !multi.profiles.isEmpty {
            let entry = multi.profiles.first(where: { $0.profile.id == multi.activeProfileId }) ?? multi.profiles[0]
            let placement = entry.settings.placementLevel.map {
                PlacementRecord(cefrLevel: $0, ceilingFreq: entry.settings.placementCeilingFreq, baselineWords: entry.settings.placementBaselineWords)
            }
            return FullBackupData(
                favorites: entry.favorites,
                flashcards: entry.flashcards,
                dailyLogs: entry.dailyLogs,
                placement: placement
            )
        }
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
