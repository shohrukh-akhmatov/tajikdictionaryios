import Foundation
import Observation
import SwiftData
import SwiftUI

enum ThemeSetting: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum FontScaleSetting: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return String(localized: "Small")
        case .medium: return String(localized: "Medium")
        case .large: return String(localized: "Large")
        }
    }

    var multiplier: CGFloat {
        switch self {
        case .small: return 0.9
        case .medium: return 1.0
        case .large: return 1.2
        }
    }
}

@MainActor
@Observable
final class SettingsStore {
    private let defaults: UserDefaults
    private var containersByProfile: [String: ModelContainer] = [:]
    private var isReloadingProfileSettings = false

    private enum Keys {
        static let mode = "dictionary_mode"
        static let studyMode = "study_mode"
        static let theme = "appearance_theme"
        static let speechRate = "speech_rate"
        static let fontScale = "font_scale"
        static let dailyGoal = "daily_goal"
        static let placementLevel = "placement_level"
        static let placementCeilingFreq = "placement_ceiling_freq"
        static let placementBaselineWords = "placement_baseline_words"
        static let hasCompletedPlacement = "has_completed_placement"
        static let hasCompletedOnboarding = "has_completed_onboarding"

        // Multi-user profile registry keys
        static let profilesData = "profiles_json_v1"
        static let activeProfileId = "active_profile_id"
        static let profileStatsData = "profile_stats_json_v1"
        static let askWhoIsLearning = "ask_who_is_learning"
        static let lastProfileSwitchEpoch = "last_profile_switch_epoch"

        /// Any of these present means the app was used before onboarding existed.
        static let legacyUsageMarkers = [mode, theme, speechRate, fontScale, dailyGoal, hasCompletedPlacement]

        static func studyMode(for profileId: String) -> String { "study_mode_\(profileId)" }
        static func dailyGoal(for profileId: String) -> String { "daily_goal_\(profileId)" }
        static func placementLevel(for profileId: String) -> String { "placement_level_\(profileId)" }
        static func placementCeilingFreq(for profileId: String) -> String { "placement_ceiling_freq_\(profileId)" }
        static func placementBaselineWords(for profileId: String) -> String { "placement_baseline_words_\(profileId)" }
        static func hasCompletedPlacement(for profileId: String) -> String { "has_completed_placement_\(profileId)" }
    }

    // MARK: - Multi-user profiles

    var profiles: [LearnerProfile] {
        didSet {
            if let data = try? JSONEncoder().encode(profiles) {
                defaults.set(data, forKey: Keys.profilesData)
            }
        }
    }

    var activeProfileId: String {
        didSet {
            defaults.set(activeProfileId, forKey: Keys.activeProfileId)
        }
    }

    var activeProfile: LearnerProfile {
        profiles.first(where: { $0.id == activeProfileId })
            ?? profiles.first
            ?? LearnerProfile.defaultProfile()
    }

    var profileStats: [String: ProfileStatsSnapshot] {
        didSet {
            if let data = try? JSONEncoder().encode(Array(profileStats.values)) {
                defaults.set(data, forKey: Keys.profileStatsData)
            }
        }
    }

    var askWhoIsLearning: Bool {
        didSet { defaults.set(askWhoIsLearning, forKey: Keys.askWhoIsLearning) }
    }

    var lastProfileSwitchEpoch: TimeInterval {
        didSet { defaults.set(lastProfileSwitchEpoch, forKey: Keys.lastProfileSwitchEpoch) }
    }

    // MARK: - Device-wide & per-profile settings

    /// First-launch welcome flow (language, daily goal, level) has been finished or skipped.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    var mode: DictionaryMode {
        didSet { defaults.set(mode.rawValue, forKey: Keys.mode) }
    }

    /// Per-profile language the learning game pairs with Tajik (Russian or English). Independent of the dictionary mode.
    var studyMode: DictionaryMode {
        didSet {
            guard !isReloadingProfileSettings else { return }
            defaults.set(studyMode.rawValue, forKey: Keys.studyMode(for: activeProfile.id))
            if activeProfile.id == LearnerProfile.defaultProfileId {
                defaults.set(studyMode.rawValue, forKey: Keys.studyMode)
            }
        }
    }

    var theme: ThemeSetting {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    /// 0.42 (slow ~0.75x) or 0.5 (Apple's default normal rate).
    var slowSpeech: Bool {
        didSet { defaults.set(slowSpeech, forKey: Keys.speechRate) }
    }

    var fontScale: FontScaleSetting {
        didSet { defaults.set(fontScale.rawValue, forKey: Keys.fontScale) }
    }

    var dailyGoal: Int {
        didSet {
            guard !isReloadingProfileSettings else { return }
            defaults.set(dailyGoal, forKey: Keys.dailyGoal(for: activeProfile.id))
            if activeProfile.id == LearnerProfile.defaultProfileId {
                defaults.set(dailyGoal, forKey: Keys.dailyGoal)
            }
        }
    }

    var placementLevelRaw: String {
        didSet {
            guard !isReloadingProfileSettings else { return }
            defaults.set(placementLevelRaw, forKey: Keys.placementLevel(for: activeProfile.id))
            if activeProfile.id == LearnerProfile.defaultProfileId {
                defaults.set(placementLevelRaw, forKey: Keys.placementLevel)
            }
        }
    }

    var placementCeilingFreq: Int {
        didSet {
            guard !isReloadingProfileSettings else { return }
            defaults.set(placementCeilingFreq, forKey: Keys.placementCeilingFreq(for: activeProfile.id))
            if activeProfile.id == LearnerProfile.defaultProfileId {
                defaults.set(placementCeilingFreq, forKey: Keys.placementCeilingFreq)
            }
        }
    }

    var placementBaselineWords: Int {
        didSet {
            guard !isReloadingProfileSettings else { return }
            defaults.set(placementBaselineWords, forKey: Keys.placementBaselineWords(for: activeProfile.id))
            if activeProfile.id == LearnerProfile.defaultProfileId {
                defaults.set(placementBaselineWords, forKey: Keys.placementBaselineWords)
            }
        }
    }

    var hasCompletedPlacement: Bool {
        didSet {
            guard !isReloadingProfileSettings else { return }
            defaults.set(hasCompletedPlacement, forKey: Keys.hasCompletedPlacement(for: activeProfile.id))
            if activeProfile.id == LearnerProfile.defaultProfileId {
                defaults.set(hasCompletedPlacement, forKey: Keys.hasCompletedPlacement)
            }
        }
    }

    var placementLevel: CefrLevel? {
        hasCompletedPlacement ? CefrLevel(rawValue: placementLevelRaw) : nil
    }

    var avSpeechRate: Float {
        slowSpeech ? 0.38 : 0.5
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loadedProfiles: [LearnerProfile] = {
            if let data = defaults.data(forKey: Keys.profilesData),
               let list = try? JSONDecoder().decode([LearnerProfile].self, from: data),
               !list.isEmpty {
                return list
            }
            return [LearnerProfile.defaultProfile()]
        }()
        let savedActiveId = defaults.string(forKey: Keys.activeProfileId)
        let resolvedActive = loadedProfiles.first(where: { $0.id == savedActiveId }) ?? loadedProfiles[0]

        let loadedStats: [String: ProfileStatsSnapshot] = {
            if let data = defaults.data(forKey: Keys.profileStatsData),
               let list = try? JSONDecoder().decode([ProfileStatsSnapshot].self, from: data) {
                return Dictionary(uniqueKeysWithValues: list.map { ($0.profileId, $0) })
            }
            return [:]
        }()

        self.profiles = loadedProfiles
        self.activeProfileId = resolvedActive.id
        self.profileStats = loadedStats
        self.askWhoIsLearning = defaults.object(forKey: Keys.askWhoIsLearning) as? Bool ?? true
        self.lastProfileSwitchEpoch = defaults.double(forKey: Keys.lastProfileSwitchEpoch)

        let savedMode = defaults.string(forKey: Keys.mode).flatMap(DictionaryMode.init(rawValue:)) ?? .tjRu
        let savedTheme = defaults.string(forKey: Keys.theme).flatMap(ThemeSetting.init(rawValue:)) ?? .system
        let savedScale = defaults.string(forKey: Keys.fontScale).flatMap(FontScaleSetting.init(rawValue:)) ?? .medium
        self.mode = savedMode
        self.theme = savedTheme
        self.slowSpeech = defaults.bool(forKey: Keys.speechRate)
        self.fontScale = savedScale

        // Placeholder initialization before loading active profile's scoped values
        self.studyMode = .tjEn
        self.dailyGoal = resolvedActive.kind.defaultDailyGoal
        self.placementLevelRaw = CefrLevel.a0.rawValue
        self.placementCeilingFreq = 100
        self.placementBaselineWords = 0
        self.hasCompletedPlacement = false

        // Existing users who already changed a setting never see onboarding; RootView also checks for saved data.
        self.hasCompletedOnboarding = defaults.object(forKey: Keys.hasCompletedOnboarding) as? Bool
            ?? Keys.legacyUsageMarkers.contains { defaults.object(forKey: $0) != nil }

        reloadActiveProfileSettings()
    }

    private func reloadActiveProfileSettings() {
        isReloadingProfileSettings = true
        defer { isReloadingProfileSettings = false }

        let profile = activeProfile
        let isDef = profile.id == LearnerProfile.defaultProfileId

        let studyRaw = defaults.string(forKey: Keys.studyMode(for: profile.id))
            ?? (isDef ? defaults.string(forKey: Keys.studyMode) : nil)
        self.studyMode = studyRaw.flatMap(DictionaryMode.init(rawValue:)) ?? .tjEn

        let scopedGoal = defaults.integer(forKey: Keys.dailyGoal(for: profile.id))
        let fallbackGoal = isDef ? defaults.integer(forKey: Keys.dailyGoal) : 0
        let resolvedGoal = scopedGoal > 0 ? scopedGoal : (fallbackGoal > 0 ? fallbackGoal : profile.kind.defaultDailyGoal)
        self.dailyGoal = resolvedGoal

        let levelRaw = defaults.string(forKey: Keys.placementLevel(for: profile.id))
            ?? (isDef ? defaults.string(forKey: Keys.placementLevel) : nil)
            ?? CefrLevel.a0.rawValue
        self.placementLevelRaw = levelRaw

        let scopedCeiling = defaults.integer(forKey: Keys.placementCeilingFreq(for: profile.id))
        let fallbackCeiling = isDef ? defaults.integer(forKey: Keys.placementCeilingFreq) : 0
        let resolvedCeiling = scopedCeiling > 0 ? scopedCeiling : (fallbackCeiling > 0 ? fallbackCeiling : 100)
        self.placementCeilingFreq = (40...100).contains(resolvedCeiling) ? resolvedCeiling : 100

        let scopedBaseline = defaults.object(forKey: Keys.placementBaselineWords(for: profile.id)) as? Int
        let fallbackBaseline = isDef ? defaults.integer(forKey: Keys.placementBaselineWords) : 0
        self.placementBaselineWords = scopedBaseline ?? fallbackBaseline

        let scopedHasPlacement = defaults.object(forKey: Keys.hasCompletedPlacement(for: profile.id)) as? Bool
        let fallbackHasPlacement = isDef ? defaults.bool(forKey: Keys.hasCompletedPlacement) : false
        self.hasCompletedPlacement = scopedHasPlacement ?? fallbackHasPlacement
    }

    func applyPlacement(_ result: PlacementResult) {
        placementLevelRaw = result.cefrLevel.rawValue
        placementCeilingFreq = result.cefrLevel.recommendedCeilingFrequency
        placementBaselineWords = result.cefrLevel.baselineKnownWords
        hasCompletedPlacement = true
    }

    // MARK: - Profile CRUD (Max 3 profiles per phone)

    @discardableResult
    func addProfile(
        name: String,
        avatar: String,
        colorHex: String,
        kind: ProfileKind = .adult,
        switchToNew: Bool = true,
        now: Date = .now
    ) -> LearnerProfile? {
        guard profiles.count < LearnerProfile.maxProfiles else { return nil }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        let cleanName = trimmed.isEmpty ? LearnerProfile.defaultName : trimmed
        let cleanAvatar = avatar.isEmpty ? LearnerProfile.defaultAvatar : avatar
        let cleanColor = colorHex.isEmpty ? LearnerProfile.defaultColor : colorHex
        let newId = "p_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
        let profile = LearnerProfile(
            id: newId,
            name: cleanName,
            avatar: cleanAvatar,
            colorHex: cleanColor,
            kind: kind,
            createdAtMs: Int64(now.timeIntervalSince1970 * 1000)
        )
        defaults.set(kind.defaultDailyGoal, forKey: Keys.dailyGoal(for: newId))
        defaults.set(DictionaryMode.tjEn.rawValue, forKey: Keys.studyMode(for: newId))
        profiles.append(profile)
        if switchToNew {
            switchProfile(to: newId, now: now)
        }
        return profile
    }

    func updateProfile(
        id: String,
        name: String,
        avatar: String,
        colorHex: String,
        kind: ProfileKind
    ) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        let cleanName = trimmed.isEmpty ? LearnerProfile.defaultName : trimmed
        profiles = profiles.map { existing in
            guard existing.id == id else { return existing }
            return LearnerProfile(
                id: existing.id,
                name: cleanName,
                avatar: avatar.isEmpty ? existing.avatar : avatar,
                colorHex: colorHex.isEmpty ? existing.colorHex : colorHex,
                kind: kind,
                createdAtMs: existing.createdAtMs
            )
        }
    }

    func switchProfile(to id: String, now: Date = .now) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileId = id
        lastProfileSwitchEpoch = now.timeIntervalSince1970
        reloadActiveProfileSettings()
    }

    func recordProfileConfirmed(now: Date = .now) {
        lastProfileSwitchEpoch = now.timeIntervalSince1970
    }

    @discardableResult
    func deleteProfile(id: String, now: Date = .now) -> Bool {
        guard profiles.count > 1, profiles.contains(where: { $0.id == id }) else { return false }
        profiles.removeAll { $0.id == id }
        clearScopedKeys(for: id)
        profileStats.removeValue(forKey: id)
        containersByProfile.removeValue(forKey: id)
        Self.deleteStoreFiles(for: id)
        if activeProfileId == id || !profiles.contains(where: { $0.id == activeProfileId }) {
            activeProfileId = profiles[0].id
            lastProfileSwitchEpoch = now.timeIntervalSince1970
            reloadActiveProfileSettings()
        }
        return true
    }

    func updateProfileStats(_ snapshot: ProfileStatsSnapshot) {
        profileStats[snapshot.profileId] = snapshot
    }

    func profileSettingsBackup(for profileId: String) -> FavoritesBackup.ProfileSettingsBackup {
        let profile = profiles.first(where: { $0.id == profileId }) ?? LearnerProfile.defaultProfile()
        let isDef = profileId == LearnerProfile.defaultProfileId
        let studyRaw = defaults.string(forKey: Keys.studyMode(for: profileId))
            ?? (isDef ? defaults.string(forKey: Keys.studyMode) : nil)
            ?? DictionaryMode.tjEn.rawValue
        let scopedGoal = defaults.integer(forKey: Keys.dailyGoal(for: profileId))
        let fallbackGoal = isDef ? defaults.integer(forKey: Keys.dailyGoal) : 0
        let goal = scopedGoal > 0 ? scopedGoal : (fallbackGoal > 0 ? fallbackGoal : profile.kind.defaultDailyGoal)
        let hasPlacement = (defaults.object(forKey: Keys.hasCompletedPlacement(for: profileId)) as? Bool)
            ?? (isDef ? defaults.bool(forKey: Keys.hasCompletedPlacement) : false)
        let levelRaw: String? = hasPlacement
            ? (defaults.string(forKey: Keys.placementLevel(for: profileId))
                ?? (isDef ? defaults.string(forKey: Keys.placementLevel) : nil))
            : nil
        let scopedCeiling = defaults.integer(forKey: Keys.placementCeilingFreq(for: profileId))
        let fallbackCeiling = isDef ? defaults.integer(forKey: Keys.placementCeilingFreq) : 0
        let ceiling = scopedCeiling > 0 ? scopedCeiling : (fallbackCeiling > 0 ? fallbackCeiling : 100)
        let baseline = (defaults.object(forKey: Keys.placementBaselineWords(for: profileId)) as? Int)
            ?? (isDef ? defaults.integer(forKey: Keys.placementBaselineWords) : 0)
        return FavoritesBackup.ProfileSettingsBackup(
            studyMode: studyRaw,
            dailyGoal: goal,
            placementLevel: levelRaw,
            placementCeilingFreq: ceiling,
            placementBaselineWords: baseline
        )
    }

    @discardableResult
    func upsertImportedProfile(
        _ incoming: LearnerProfile,
        settingsBackup: FavoritesBackup.ProfileSettingsBackup,
        makeActive: Bool = false
    ) -> LearnerProfile? {
        let target: LearnerProfile
        if let idx = profiles.firstIndex(where: {
            $0.id == incoming.id || $0.name.caseInsensitiveCompare(incoming.name) == .orderedSame
        }) {
            let existing = profiles[idx]
            let merged = LearnerProfile(
                id: existing.id,
                name: incoming.name.isEmpty ? existing.name : incoming.name,
                avatar: incoming.avatar.isEmpty ? existing.avatar : incoming.avatar,
                colorHex: incoming.colorHex.isEmpty ? existing.colorHex : incoming.colorHex,
                kind: incoming.kind,
                createdAtMs: existing.createdAtMs
            )
            profiles[idx] = merged
            target = merged
        } else if profiles.count < LearnerProfile.maxProfiles {
            profiles.append(incoming)
            target = incoming
        } else {
            return nil
        }

        let modeVal = DictionaryMode(rawValue: settingsBackup.studyMode) ?? .tjEn
        defaults.set(modeVal.rawValue, forKey: Keys.studyMode(for: target.id))
        if target.id == LearnerProfile.defaultProfileId {
            defaults.set(modeVal.rawValue, forKey: Keys.studyMode)
        }
        let goalVal = settingsBackup.dailyGoal > 0 ? settingsBackup.dailyGoal : target.kind.defaultDailyGoal
        defaults.set(goalVal, forKey: Keys.dailyGoal(for: target.id))
        if target.id == LearnerProfile.defaultProfileId {
            defaults.set(goalVal, forKey: Keys.dailyGoal)
        }
        if let code = settingsBackup.placementLevel, let cefr = CefrLevel(rawValue: code) {
            defaults.set(cefr.rawValue, forKey: Keys.placementLevel(for: target.id))
            defaults.set(settingsBackup.placementCeilingFreq, forKey: Keys.placementCeilingFreq(for: target.id))
            defaults.set(settingsBackup.placementBaselineWords, forKey: Keys.placementBaselineWords(for: target.id))
            defaults.set(true, forKey: Keys.hasCompletedPlacement(for: target.id))
            if target.id == LearnerProfile.defaultProfileId {
                defaults.set(cefr.rawValue, forKey: Keys.placementLevel)
                defaults.set(settingsBackup.placementCeilingFreq, forKey: Keys.placementCeilingFreq)
                defaults.set(settingsBackup.placementBaselineWords, forKey: Keys.placementBaselineWords)
                defaults.set(true, forKey: Keys.hasCompletedPlacement)
            }
        }
        if makeActive {
            activeProfileId = target.id
        }
        reloadActiveProfileSettings()
        return target
    }

    private func clearScopedKeys(for profileId: String) {
        defaults.removeObject(forKey: Keys.studyMode(for: profileId))
        defaults.removeObject(forKey: Keys.dailyGoal(for: profileId))
        defaults.removeObject(forKey: Keys.placementLevel(for: profileId))
        defaults.removeObject(forKey: Keys.placementCeilingFreq(for: profileId))
        defaults.removeObject(forKey: Keys.placementBaselineWords(for: profileId))
        defaults.removeObject(forKey: Keys.hasCompletedPlacement(for: profileId))
    }

    // MARK: - Per-Profile SwiftData ModelContainer & Cloud/File Backup

    var activeModelContainer: ModelContainer {
        modelContainer(for: activeProfile.id)
    }

    func modelContainer(for profileId: String) -> ModelContainer {
        if let cached = containersByProfile[profileId] {
            return cached
        }
        let schema = Schema([
            FavoriteItem.self,
            HistoryItem.self,
            FlashcardProgress.self,
            DailyStudyLog.self,
        ])
        let container: ModelContainer
        if profileId == LearnerProfile.defaultProfileId {
            container = try! ModelContainer(for: schema)
        } else {
            let url = Self.storeURL(for: profileId)
            let config = ModelConfiguration(schema: schema, url: url)
            container = (try? ModelContainer(for: schema, configurations: [config]))
                ?? (try! ModelContainer(for: schema))
        }
        containersByProfile[profileId] = container
        return container
    }

    static func learningDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("TajikDictionary/learning", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func storeURL(for profileId: String) -> URL {
        let safe = profileId.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        return learningDirectoryURL().appendingPathComponent("learning_\(safe).store")
    }

    static func deleteStoreFiles(for profileId: String) {
        guard profileId != LearnerProfile.defaultProfileId else { return }
        let base = storeURL(for: profileId)
        for suffix in ["", "-wal", "-shm"] {
            let target = URL(fileURLWithPath: base.path + suffix)
            try? FileManager.default.removeItem(at: target)
        }
    }

    /// Exports all learner profiles (up to 3) into a cross-platform `ProfileBackup v1` JSON Data payload,
    /// and writes a local/iCloud backup snapshot automatically.
    func exportAllProfilesData() throws -> Data {
        var entries: [FavoritesBackup.ProfileEntryBackup] = []
        for profile in profiles {
            let ctx = modelContainer(for: profile.id).mainContext
            let favs = (try? ctx.fetch(FetchDescriptor<FavoriteItem>())) ?? []
            let cards = (try? ctx.fetch(FetchDescriptor<FlashcardProgress>())) ?? []
            let logs = (try? ctx.fetch(FetchDescriptor<DailyStudyLog>())) ?? []
            let favRecords = favs.map { item in
                FavoritesBackup.Record(
                    entryId: item.entryId,
                    lang: item.lang,
                    headword: item.headword,
                    preview: item.preview,
                    addedAt: Int64(item.addedAt.timeIntervalSince1970 * 1000)
                )
            }
            let cardRecords = cards.map { item in
                FavoritesBackup.FlashcardRecord(
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
            let logRecords = logs.map { item in
                FavoritesBackup.DailyLogRecord(
                    dateKey: item.dateKey,
                    wordsReviewed: item.wordsReviewed,
                    wordsLearned: item.wordsLearned,
                    xpEarned: item.xpEarned,
                    roundsCompleted: item.roundsCompleted,
                    studySeconds: item.studySeconds,
                    correctReviews: item.correctReviews
                )
            }
            entries.append(
                FavoritesBackup.ProfileEntryBackup(
                    profile: profile,
                    settings: profileSettingsBackup(for: profile.id),
                    favorites: favRecords,
                    flashcards: cardRecords,
                    dailyLogs: logRecords
                )
            )
        }
        let data = try FavoritesBackup.encodeProfiles(profiles: entries, activeProfileId: activeProfile.id)
        saveCloudAndLocalSnapshot(data)
        return data
    }

    /// Imports either a multi-profile `ProfileBackup v1` JSON or a legacy single-profile backup (v1/v2).
    /// Returns total number of favorite + flashcard records imported across all profiles.
    @discardableResult
    func importProfilesBackup(from data: Data) throws -> Int {
        let jsonText = String(data: data, encoding: .utf8) ?? ""
        let isMultiFormat = jsonText.contains("\"profiles\"")
        if !isMultiFormat {
            let full = try FavoritesBackup.decodeFull(from: data)
            let ctx = activeModelContainer.mainContext
            let count = Self.importRecords(into: ctx, favorites: full.favorites, flashcards: full.flashcards, dailyLogs: full.dailyLogs)
            if let p = full.placement, let cefr = CefrLevel(rawValue: p.cefrLevel) {
                placementLevelRaw = cefr.rawValue
                placementCeilingFreq = p.ceilingFreq
                placementBaselineWords = p.baselineWords
                hasCompletedPlacement = true
            }
            refreshStats(for: activeProfile.id, context: ctx)
            return count
        }

        let multi = try FavoritesBackup.decodeProfiles(from: data)
        var totalImported = 0
        for entry in multi.profiles {
            let makeActive = entry.profile.id == multi.activeProfileId
            guard let targetProfile = upsertImportedProfile(
                entry.profile,
                settingsBackup: entry.settings,
                makeActive: makeActive
            ) else { continue }
            let ctx = modelContainer(for: targetProfile.id).mainContext
            totalImported += Self.importRecords(into: ctx, favorites: entry.favorites, flashcards: entry.flashcards, dailyLogs: entry.dailyLogs)
            refreshStats(for: targetProfile.id, context: ctx)
        }
        reloadActiveProfileSettings()
        return totalImported
    }

    func refreshStats(for profileId: String, context: ModelContext) {
        let cards = (try? context.fetch(FetchDescriptor<FlashcardProgress>())) ?? []
        let logs = (try? context.fetch(FetchDescriptor<DailyStudyLog>())) ?? []
        let cfg = profileSettingsBackup(for: profileId)
        let placementLvl = cfg.placementLevel.flatMap(CefrLevel.init(rawValue:))
        let summary = WordGameEngine.computeSummary(
            progress: cards.map(\.snapshot),
            logs: logs.map(\.snapshot),
            dailyGoal: cfg.dailyGoal,
            lexiconStats: .fallback,
            placementLevel: placementLvl,
            placementBaselineWords: cfg.placementBaselineWords
        )
        let latestKey = logs.filter { $0.wordsReviewed > 0 }.map(\.dateKey).max()
        updateProfileStats(
            ProfileStatsSnapshot(
                profileId: profileId,
                currentStreakDays: summary.currentStreakDays,
                longestStreakDays: summary.longestStreakDays,
                totalXp: summary.totalXp,
                masteredCount: summary.masteredCount,
                knownWordsCount: summary.estimatedKnownWords,
                todayReviewed: summary.todayReviewed,
                dailyGoal: summary.dailyGoal,
                cefrCode: summary.cefrLevel.rawValue,
                lastActiveDateKey: latestKey
            )
        )
    }

    private static func importRecords(
        into modelContext: ModelContext,
        favorites: [FavoritesBackup.Record],
        flashcards: [FavoritesBackup.FlashcardRecord],
        dailyLogs: [FavoritesBackup.DailyLogRecord]
    ) -> Int {
        for record in favorites {
            let targetId = record.entryId
            let existing = (try? modelContext.fetch(
                FetchDescriptor<FavoriteItem>(predicate: #Predicate { $0.entryId == targetId })
            ))?.first
            if let existing {
                existing.lang = record.lang
                existing.headword = record.headword
                existing.preview = record.preview
            } else {
                modelContext.insert(FavoriteItem(
                    entryId: record.entryId,
                    lang: record.lang,
                    headword: record.headword,
                    preview: record.preview,
                    addedAt: Date(timeIntervalSince1970: Double(record.addedAt) / 1000.0)
                ))
            }
        }
        for card in flashcards {
            let targetId = card.entryId
            let existing = (try? modelContext.fetch(
                FetchDescriptor<FlashcardProgress>(predicate: #Predicate { $0.entryId == targetId })
            ))?.first
            let nextDate = Date(timeIntervalSince1970: Double(card.nextReviewAt) / 1000.0)
            let lastDate = card.lastReviewedAt.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
            if let existing {
                let incomingLast = card.lastReviewedAt ?? 0
                let existingLast = existing.lastReviewedAt.map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
                if incomingLast >= existingLast || card.masteryStage >= existing.masteryStage {
                    existing.repetitions = max(existing.repetitions, card.repetitions)
                    existing.intervalDays = max(existing.intervalDays, card.intervalDays)
                    existing.easeFactor = card.easeFactor
                    existing.nextReviewAt = nextDate
                    existing.masteryStage = max(existing.masteryStage, card.masteryStage)
                    existing.stabilityDays = max(existing.stabilityDays, card.stabilityDays)
                    existing.lapses = max(existing.lapses, card.lapses)
                    existing.lastReviewedAt = lastDate ?? existing.lastReviewedAt
                    existing.isKnownSkipped = existing.isKnownSkipped || card.isKnownSkipped
                }
            } else {
                modelContext.insert(FlashcardProgress(
                    entryId: card.entryId,
                    lang: card.lang,
                    headword: card.headword,
                    preview: card.preview,
                    repetitions: card.repetitions,
                    intervalDays: card.intervalDays,
                    easeFactor: card.easeFactor,
                    nextReviewAt: nextDate,
                    masteryStage: card.masteryStage,
                    stabilityDays: card.stabilityDays,
                    lapses: card.lapses,
                    lastReviewedAt: lastDate,
                    isKnownSkipped: card.isKnownSkipped
                ))
            }
        }
        for log in dailyLogs {
            let key = log.dateKey
            let existing = (try? modelContext.fetch(
                FetchDescriptor<DailyStudyLog>(predicate: #Predicate { $0.dateKey == key })
            ))?.first
            if let existing {
                existing.wordsReviewed = max(existing.wordsReviewed, log.wordsReviewed)
                existing.wordsLearned = max(existing.wordsLearned, log.wordsLearned)
                existing.xpEarned = max(existing.xpEarned, log.xpEarned)
                existing.roundsCompleted = max(existing.roundsCompleted, log.roundsCompleted)
                existing.studySeconds = max(existing.studySeconds, log.studySeconds)
                existing.correctReviews = max(existing.correctReviews, log.correctReviews)
            } else {
                modelContext.insert(DailyStudyLog(
                    dateKey: log.dateKey,
                    wordsReviewed: log.wordsReviewed,
                    wordsLearned: log.wordsLearned,
                    xpEarned: log.xpEarned,
                    roundsCompleted: log.roundsCompleted,
                    studySeconds: log.studySeconds,
                    correctReviews: log.correctReviews
                ))
            }
        }
        try? modelContext.save()
        return favorites.count + flashcards.count
    }

    private func saveCloudAndLocalSnapshot(_ data: Data) {
        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = appSupport.appendingPathComponent("TajikDictionary/Backups", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent("tajik-dictionary-profiles.json")
            try? data.write(to: fileURL, options: .atomic)
        }
        if let ubiquity = fm.url(forUbiquityContainerIdentifier: nil) {
            let docs = ubiquity.appendingPathComponent("Documents", isDirectory: true)
            try? fm.createDirectory(at: docs, withIntermediateDirectories: true)
            let cloudURL = docs.appendingPathComponent("tajik-dictionary-profiles.json")
            try? data.write(to: cloudURL, options: .atomic)
        }
    }
}
