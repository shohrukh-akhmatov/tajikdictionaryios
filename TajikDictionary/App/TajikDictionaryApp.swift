import CoreSpotlight
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

private enum AppTab: Hashable {
    case dictionary
    case saved
    case history
    case settings
}

struct RootView: View {
    @Environment(\.dictionaryRepository) private var repository
    @Environment(SettingsStore.self) private var settings
    @State private var selectedTab: AppTab = .dictionary
    @State private var deepLinkEntryId: Int64?

    var body: some View {
        TabView(selection: $selectedTab) {
            SearchView(deepLinkEntryId: $deepLinkEntryId)
                .tabItem {
                    Label(String(localized: "Dictionary"), systemImage: "character.book.closed")
                }
                .tag(AppTab.dictionary)

            FavoritesView()
                .tabItem {
                    Label(String(localized: "Saved"), systemImage: "star")
                }
                .tag(AppTab.saved)

            HistoryView()
                .tabItem {
                    Label(String(localized: "History"), systemImage: "clock")
                }
                .tag(AppTab.history)

            SettingsView()
                .tabItem {
                    Label(String(localized: "Settings"), systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .task {
            if let top = try? await repository.spotlightEntries(mode: settings.mode, limit: 250) {
                await SpotlightIndexer.indexEntries(top)
            }
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let id = SpotlightIndexer.entryId(from: activity) {
                selectedTab = .dictionary
                deepLinkEntryId = id
            }
        }
        .onOpenURL { url in
            if let id = SpotlightIndexer.entryId(from: url) {
                selectedTab = .dictionary
                deepLinkEntryId = id
            }
        }
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
        .modelContainer(for: [FavoriteItem.self, HistoryItem.self, FlashcardProgress.self])
    }
}
