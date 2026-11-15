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
        static let theme = "appearance_theme"
        static let speechRate = "speech_rate"
        static let fontScale = "font_scale"
        static let dailyGoal = "daily_goal"
    }

    var mode: DictionaryMode {
        didSet { defaults.set(mode.rawValue, forKey: Keys.mode) }
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

    var avSpeechRate: Float {
        slowSpeech ? 0.38 : 0.5
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedMode = defaults.string(forKey: Keys.mode).flatMap(DictionaryMode.init(rawValue:)) ?? .tjRu
        let savedTheme = defaults.string(forKey: Keys.theme).flatMap(ThemeSetting.init(rawValue:)) ?? .system
        let savedScale = defaults.string(forKey: Keys.fontScale).flatMap(FontScaleSetting.init(rawValue:)) ?? .medium
        let savedGoal = defaults.integer(forKey: Keys.dailyGoal)
        self.mode = savedMode
        self.theme = savedTheme
        self.slowSpeech = defaults.bool(forKey: Keys.speechRate)
        self.fontScale = savedScale
        self.dailyGoal = savedGoal > 0 ? savedGoal : 10
    }
}
