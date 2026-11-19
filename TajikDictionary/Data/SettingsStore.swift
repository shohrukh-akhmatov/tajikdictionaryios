import Foundation
import Observation
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
        /// Any of these present means the app was used before onboarding existed.
        static let legacyUsageMarkers = [mode, theme, speechRate, fontScale, dailyGoal, hasCompletedPlacement]
    }

    /// First-launch welcome flow (language, daily goal, level) has been finished or skipped.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    var mode: DictionaryMode {
        didSet { defaults.set(mode.rawValue, forKey: Keys.mode) }
    }

    /// Language the learning game pairs with Tajik (Russian or English). Independent of the dictionary mode,
    /// so switching it on the Learn screen never changes how Search behaves. Progress is shared: it is keyed by
    /// the Tajik entry, so a word learned with Russian counts as learned with English too.
    var studyMode: DictionaryMode {
        didSet { defaults.set(studyMode.rawValue, forKey: Keys.studyMode) }
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
        didSet { defaults.set(dailyGoal, forKey: Keys.dailyGoal) }
    }

    var placementLevelRaw: String {
        didSet { defaults.set(placementLevelRaw, forKey: Keys.placementLevel) }
    }

    var placementCeilingFreq: Int {
        didSet { defaults.set(placementCeilingFreq, forKey: Keys.placementCeilingFreq) }
    }

    var placementBaselineWords: Int {
        didSet { defaults.set(placementBaselineWords, forKey: Keys.placementBaselineWords) }
    }

    var hasCompletedPlacement: Bool {
        didSet { defaults.set(hasCompletedPlacement, forKey: Keys.hasCompletedPlacement) }
    }

    var placementLevel: CefrLevel? {
        hasCompletedPlacement ? CefrLevel(rawValue: placementLevelRaw) : nil
    }

    var avSpeechRate: Float {
        slowSpeech ? 0.38 : 0.5
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedMode = defaults.string(forKey: Keys.mode).flatMap(DictionaryMode.init(rawValue:)) ?? .tjRu
        let savedTheme = defaults.string(forKey: Keys.theme).flatMap(ThemeSetting.init(rawValue:)) ?? .system
        let savedScale = defaults.string(forKey: Keys.fontScale).flatMap(FontScaleSetting.init(rawValue:)) ?? .medium
        let savedGoal = defaults.integer(forKey: Keys.dailyGoal)
        let savedCeiling = defaults.integer(forKey: Keys.placementCeilingFreq)
        self.mode = savedMode
        // First launch after the update: start from the dictionary mode the user already picked.
        self.studyMode = defaults.string(forKey: Keys.studyMode).flatMap(DictionaryMode.init(rawValue:)) ?? .tjEn
        self.theme = savedTheme
        self.slowSpeech = defaults.bool(forKey: Keys.speechRate)
        self.fontScale = savedScale
        self.dailyGoal = savedGoal > 0 ? savedGoal : 10
        self.placementLevelRaw = defaults.string(forKey: Keys.placementLevel) ?? CefrLevel.a0.rawValue
        self.placementCeilingFreq = savedCeiling > 0 ? savedCeiling : 100
        self.placementBaselineWords = defaults.integer(forKey: Keys.placementBaselineWords)
        self.hasCompletedPlacement = defaults.bool(forKey: Keys.hasCompletedPlacement)
        // Existing users who already changed a setting never see onboarding; RootView also checks for saved data.
        self.hasCompletedOnboarding = defaults.object(forKey: Keys.hasCompletedOnboarding) as? Bool
            ?? Keys.legacyUsageMarkers.contains { defaults.object(forKey: $0) != nil }
    }

    func applyPlacement(_ result: PlacementResult) {
        placementLevelRaw = result.cefrLevel.rawValue
        placementCeilingFreq = result.cefrLevel.recommendedCeilingFrequency
        placementBaselineWords = result.cefrLevel.baselineKnownWords
        hasCompletedPlacement = true
    }
}
