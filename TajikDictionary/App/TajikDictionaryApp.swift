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
    case learn
    case saved
    case history
    case settings
}

struct RootView: View {
    @Environment(\.dictionaryRepository) private var repository
    @Environment(SettingsStore.self) private var settings
    @State private var selectedTab: AppTab = .dictionary
    @State private var deepLinkEntryId: Int64?
    @Environment(\.modelContext) private var modelContext
    @State private var showOnboarding = false
    @State private var placementAfterOnboarding = false
    @State private var showPlacementTest = false

    var body: some View {
        TabView(selection: $selectedTab) {
            SearchView(deepLinkEntryId: $deepLinkEntryId)
                .stickyBannerAd()
                .tabItem {
                    Label(String(localized: "Dictionary"), systemImage: "character.book.closed")
                }
                .tag(AppTab.dictionary)

            LearnView()
                .stickyBannerAd()
                .tabItem {
                    Label(String(localized: "Learn"), systemImage: "graduationcap")
                }
                .tag(AppTab.learn)

            FavoritesView()
                .stickyBannerAd()
                .tabItem {
                    Label(String(localized: "Saved"), systemImage: "star")
                }
                .tag(AppTab.saved)

            HistoryView()
                .stickyBannerAd()
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
            checkOnboarding()
            // On first launch the consent form waits until onboarding (and the optional test) is done.
            if !showOnboarding { await AdsManager.shared.start() }
        }
        .fullScreenCover(isPresented: $showOnboarding, onDismiss: {
            // Present the test only after the onboarding cover is gone; two covers can't animate at once.
            if placementAfterOnboarding {
                placementAfterOnboarding = false
                selectedTab = .learn
                showPlacementTest = true
            } else {
                Task { await AdsManager.shared.start() }
            }
        }) {
            OnboardingView { startPlacement in
                settings.hasCompletedOnboarding = true
                placementAfterOnboarding = startPlacement
                showOnboarding = false
            }
        }
        .fullScreenCover(isPresented: $showPlacementTest, onDismiss: {
            Task { await AdsManager.shared.start() }
        }) {
            PlacementTestView()
        }
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

    /// Shows onboarding on a true first launch. Users who already have saved words, history or study
    /// progress (from before onboarding existed) are marked done silently.
    private func checkOnboarding() {
        guard !settings.hasCompletedOnboarding else { return }
        let hasData = ((try? modelContext.fetchCount(FetchDescriptor<HistoryItem>())) ?? 0) > 0
            || ((try? modelContext.fetchCount(FetchDescriptor<FavoriteItem>())) ?? 0) > 0
            || ((try? modelContext.fetchCount(FetchDescriptor<FlashcardProgress>())) ?? 0) > 0
        if hasData {
            settings.hasCompletedOnboarding = true
        } else {
            showOnboarding = true
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
        .modelContainer(for: [FavoriteItem.self, HistoryItem.self, FlashcardProgress.self, DailyStudyLog.self])
    }
}
