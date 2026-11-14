import SwiftData
import SwiftUI

private struct DictionaryRepositoryKey: EnvironmentKey {
    static let defaultValue: DictionaryRepository = {
        try! DictionaryRepository()
    }()
}

extension EnvironmentValues {
    var dictionaryRepository: DictionaryRepository {
        get { self[DictionaryRepositoryKey.self] }
        set { self[DictionaryRepositoryKey.self] = newValue }
    }
}

struct RootView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        TabView {
            SearchView()
                .tabItem {
                    Label(String(localized: "Dictionary"), systemImage: "character.book.closed")
                }

            FavoritesView()
                .tabItem {
                    Label(String(localized: "Saved"), systemImage: "star")
                }

            HistoryView()
                .tabItem {
                    Label(String(localized: "History"), systemImage: "clock")
                }

            SettingsView()
                .tabItem {
                    Label(String(localized: "Settings"), systemImage: "gearshape")
                }
        }
        .preferredColorScheme(settings.theme.colorScheme)
    }
}

@main
struct TajikDictionaryApp: App {
    @State private var settings = SettingsStore()
    private let repository = try! DictionaryRepository()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(\.dictionaryRepository, repository)
        }
        .modelContainer(for: [FavoriteItem.self, HistoryItem.self])
    }
}
