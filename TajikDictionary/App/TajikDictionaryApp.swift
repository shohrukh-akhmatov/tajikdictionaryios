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
                .id(settings.activeProfileId)
                .stickyBannerAd()
                .tabItem {
                    Label(String(localized: "Dictionary"), systemImage: "character.book.closed")
                }
                .tag(AppTab.dictionary)

            LearnView()
                .id(settings.activeProfileId)
                .stickyBannerAd()
                .tabItem {
                    Label(String(localized: "Learn"), systemImage: "graduationcap")
                }
                .tag(AppTab.learn)

            FavoritesView()
                .id(settings.activeProfileId)
                .stickyBannerAd()
                .tabItem {
                    Label(String(localized: "Saved"), systemImage: "star")
                }
                .tag(AppTab.saved)

            HistoryView()
                .id(settings.activeProfileId)
                .stickyBannerAd()
                .tabItem {
                    Label(String(localized: "History"), systemImage: "clock")
                }
                .tag(AppTab.history)

            SettingsView()
                .id(settings.activeProfileId)
                .tabItem {
                    Label(String(localized: "Settings"), systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .task(id: settings.activeProfileId) {
            await relinkUserDataIfNeeded()
            settings.refreshStats(for: settings.activeProfile.id, context: modelContext)
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

    /// Re-links saved Favorites, History, and Flashcards by `(lang, headword)` whenever `dictionary.sqlite`
    /// `data_version` changes so user records survive dictionary rebuilds without colliding on `@Attribute(.unique) entryId`.
    @MainActor
    private func relinkUserDataIfNeeded() async {
        guard let info = try? await repository.info(), !info.dataVersion.isEmpty else { return }
        let defaultsKey = "relinked_data_version_\(settings.activeProfile.id)"
        if UserDefaults.standard.string(forKey: defaultsKey) == info.dataVersion {
            return
        }

        var didChange = false

        if let favorites = try? modelContext.fetch(FetchDescriptor<FavoriteItem>()) {
            var byId = Dictionary(uniqueKeysWithValues: favorites.map { ($0.entryId, $0) })
            for item in favorites {
                if let current = try? await repository.entry(id: item.entryId),
                   current.language.rawValue == item.lang,
                   current.headword.caseInsensitiveCompare(item.headword) == .orderedSame {
                    continue
                }
                guard let newId = try? await repository.resolveEntryId(lang: item.lang, headword: item.headword) else { continue }
                let newHeadword = (try? await repository.entry(id: newId))?.headword ?? item.headword
                if newId != item.entryId {
                    let oldId = item.entryId
                    if let existing = byId[newId], existing !== item {
                        if item.addedAt < existing.addedAt { existing.addedAt = item.addedAt }
                        existing.headword = newHeadword
                        modelContext.delete(item)
                        byId.removeValue(forKey: oldId)
                    } else {
                        byId.removeValue(forKey: oldId)
                        item.entryId = newId
                        item.headword = newHeadword
                        byId[newId] = item
                    }
                    didChange = true
                } else if item.headword != newHeadword {
                    item.headword = newHeadword
                    didChange = true
                }
            }
        }

        if let historyItems = try? modelContext.fetch(FetchDescriptor<HistoryItem>()) {
            var byId = Dictionary(uniqueKeysWithValues: historyItems.map { ($0.entryId, $0) })
            for item in historyItems {
                if let current = try? await repository.entry(id: item.entryId),
                   current.language.rawValue == item.lang,
                   current.headword.caseInsensitiveCompare(item.headword) == .orderedSame {
                    continue
                }
                guard let newId = try? await repository.resolveEntryId(lang: item.lang, headword: item.headword) else { continue }
                let newHeadword = (try? await repository.entry(id: newId))?.headword ?? item.headword
                if newId != item.entryId {
                    let oldId = item.entryId
                    if let existing = byId[newId], existing !== item {
                        if item.viewedAt > existing.viewedAt { existing.viewedAt = item.viewedAt }
                        existing.headword = newHeadword
                        modelContext.delete(item)
                        byId.removeValue(forKey: oldId)
                    } else {
                        byId.removeValue(forKey: oldId)
                        item.entryId = newId
                        item.headword = newHeadword
                        byId[newId] = item
                    }
                    didChange = true
                } else if item.headword != newHeadword {
                    item.headword = newHeadword
                    didChange = true
                }
            }
        }

        if let cards = try? modelContext.fetch(FetchDescriptor<FlashcardProgress>()) {
            var byId = Dictionary(uniqueKeysWithValues: cards.map { ($0.entryId, $0) })
            for card in cards {
                if let current = try? await repository.entry(id: card.entryId),
                   current.language.rawValue == card.lang,
                   current.headword.caseInsensitiveCompare(card.headword) == .orderedSame {
                    continue
                }
                guard let newId = try? await repository.resolveEntryId(lang: card.lang, headword: card.headword) else { continue }
                let newHeadword = (try? await repository.entry(id: newId))?.headword ?? card.headword
                if newId != card.entryId {
                    let oldId = card.entryId
                    if let existing = byId[newId], existing !== card {
                        existing.headword = newHeadword
                        existing.repetitions = max(existing.repetitions, card.repetitions)
                        existing.intervalDays = max(existing.intervalDays, card.intervalDays)
                        existing.masteryStage = max(existing.masteryStage, card.masteryStage)
                        existing.stabilityDays = max(existing.stabilityDays, card.stabilityDays)
                        existing.lapses = max(existing.lapses, card.lapses)
                        existing.isKnownSkipped = existing.isKnownSkipped || card.isKnownSkipped
                        modelContext.delete(card)
                        byId.removeValue(forKey: oldId)
                    } else {
                        byId.removeValue(forKey: oldId)
                        card.entryId = newId
                        card.headword = newHeadword
                        byId[newId] = card
                    }
                    didChange = true
                } else if card.headword != newHeadword {
                    card.headword = newHeadword
                    didChange = true
                }
            }
        }

        if didChange {
            try? modelContext.save()
        }
        UserDefaults.standard.set(info.dataVersion, forKey: defaultsKey)
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
                .modelContainer(settings.activeModelContainer)
        }
    }
}
