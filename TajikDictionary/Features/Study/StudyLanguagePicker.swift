import SwiftUI

/// Segmented "Tajik ⇄ [Russian | English]" switch for the Learn screen's word trainer card.
/// Drives `SettingsStore.studyMode` (game, flashcards, placement test), never the dictionary mode.
struct StudyLanguagePicker: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        HStack(spacing: 10) {
            Text(verbatim: "\(Language.tajik.displayName) ⇄")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize()
            Picker(String(localized: "Learning language"), selection: $settings.studyMode) {
                ForEach(DictionaryMode.allCases) { mode in
                    Text(mode.partner.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Learning language"))
    }
}

/// Compact title-bar menu inside the game: shows the deck title and "TJ ⇄ RU ▾"; changing it restarts the round.
struct StudyLanguageMenu: View {
    let title: String

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Menu {
            Picker(String(localized: "Learning language"), selection: $settings.studyMode) {
                ForEach(DictionaryMode.allCases) { mode in
                    Text(mode.partner.displayName).tag(mode)
                }
            }
        } label: {
            VStack(spacing: 0) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    Text(verbatim: "TJ ⇄ \(settings.studyMode.partner.tag)")
                    Image(systemName: "chevron.down")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
            }
        }
        .accessibilityLabel(Text(verbatim: "\(title), \(String(localized: "Learning language")): \(settings.studyMode.partner.displayName)"))
    }
}
