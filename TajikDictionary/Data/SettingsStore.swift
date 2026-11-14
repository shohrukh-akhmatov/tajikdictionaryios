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

@MainActor
@Observable
final class SettingsStore {
    private let defaults: UserDefaults
    private enum Keys {
        static let mode = "dictionary_mode"
        static let theme = "appearance_theme"
    }

    var mode: DictionaryMode {
        didSet { defaults.set(mode.rawValue, forKey: Keys.mode) }
    }

    var theme: ThemeSetting {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedMode = defaults.string(forKey: Keys.mode).flatMap(DictionaryMode.init(rawValue:)) ?? .tjRu
        let savedTheme = defaults.string(forKey: Keys.theme).flatMap(ThemeSetting.init(rawValue:)) ?? .system
        self.mode = savedMode
        self.theme = savedTheme
    }
}
