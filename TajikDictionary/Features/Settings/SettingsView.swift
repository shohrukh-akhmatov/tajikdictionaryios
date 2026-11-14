import SwiftUI

struct SettingsView: View {
    @Environment(\.dictionaryRepository) private var repository
    @Environment(SettingsStore.self) private var settings
    @State private var info: DictionaryInfo?

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section(String(localized: "Dictionary mode")) {
                    ModeSwitcher(mode: $settings.mode)
                }

                Section(String(localized: "Appearance")) {
                    Picker(String(localized: "Theme"), selection: $settings.theme) {
                        ForEach(ThemeSetting.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(String(localized: "About")) {
                    LabeledContent(String(localized: "App"), value: "Tajik Dictionary 0.1.0")
                    LabeledContent(String(localized: "Dictionary version"), value: info?.dataVersion ?? "…")
                    if let stats = info?.stats, !stats.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Offline word counts"))
                            Text(stats)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "mailto:support@tajikdictionary.tj?subject=Tajik%20Dictionary%20Feedback")!) {
                        Label(String(localized: "Report a mistake / Suggest a word"), systemImage: "envelope")
                    }
                }
            }
            .navigationTitle(String(localized: "Settings"))
            .task {
                info = try? await repository.info()
            }
        }
    }
}
