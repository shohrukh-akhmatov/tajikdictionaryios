import SwiftData
import SwiftUI

struct LearnView: View {
    @Environment(\.dictionaryRepository) private var repository
    @Environment(SettingsStore.self) private var settings

    @Query private var progress: [FlashcardProgress]
    @Query private var dailyLogs: [DailyStudyLog]
    @Query(sort: \FavoriteItem.addedAt, order: .reverse) private var favorites: [FavoriteItem]

    @State private var topics: [TopicCount] = []
    @State private var lexiconStats: LexiconStats = .fallback
    @State private var selectedSource: GameDeckSource = .smartMix
    @State private var activeGameSource: GameDeckSource?
    @State private var showPlacementTest = false

    private var weakWordsCount: Int {
        progress.filter {
            !$0.isKnownSkipped && ($0.lapses > 0 || ($0.lastReviewedAt != nil && $0.masteryStage <= 1) || $0.stabilityDays < 2.0)
        }.count
    }

    private var summary: GamificationSummary {
        WordGameEngine.computeSummary(
            progress: progress.map(\.snapshot),
            logs: dailyLogs.map(\.snapshot),
            dailyGoal: settings.dailyGoal,
            lexiconStats: lexiconStats,
            placementLevel: settings.placementLevel,
            placementBaselineWords: settings.placementBaselineWords
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AppCard {
                        streakAndLevelCard
                            .padding(16)
                    }

                    wordTrainerCard

                    if !settings.hasCompletedPlacement {
                        placementPromptCard
                    }

                    progressLinkCard
                }
                .padding(16)
            }
            .background(AppTheme.background)
            .navigationTitle(String(localized: "Learn"))
            .task {
                topics = (try? await repository.topics()) ?? []
                lexiconStats = (try? await repository.lexiconStats()) ?? .fallback
            }
            .fullScreenCover(item: $activeGameSource) { source in
                WordGameView(source: source)
            }
            .fullScreenCover(isPresented: $showPlacementTest) {
                PlacementTestView()
            }
            .navigationDestination(for: Int64.self) { entryId in
                EntryDetailView(entryId: entryId)
            }
        }
    }

    private var selectedTopicName: String? {
        if case .topic(let name) = selectedSource { return name }
        return nil
    }

    private var wordTrainerCard: some View {
        AppCard(cornerRadius: 20, borderColor: AppTheme.accent.opacity(0.25)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Word Trainer"))
                            .font(.title3.bold())
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(
                            summary.dueNowCount > 0
                                ? "\(summary.dueNowCount) \(String(localized: "words due for periodic review"))"
                                : String(localized: "Frequency-ordered new words + smart reviews")
                        )
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                    }
                    Spacer()
                    if summary.dueNowCount > 0 {
                        Text("\(summary.dueNowCount)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.orange, in: Capsule())
                    }
                }

                StudyLanguagePicker()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        deckChip(title: String(localized: "Smart Mix"), source: .smartMix)
                        if summary.dueNowCount > 0 {
                            deckChip(title: "\(String(localized: "Due Reviews")) (\(summary.dueNowCount))", source: .dueReviews)
                        }
                        if weakWordsCount > 0 {
                            deckChip(title: "\(String(localized: "Weak Words")) (\(weakWordsCount))", source: .weakWords)
                        }
                        if !favorites.isEmpty {
                            deckChip(title: String(localized: "Saved"), source: .saved)
                        }
                        ForEach(topics) { item in
                            deckChip(title: TopicLocalization.displayName(for: item.topic), source: .topic(item.topic))
                        }
                    }
                }

                Button {
                    activeGameSource = selectedSource
                } label: {
                    Label(String(localized: "Start 10-Word Round"), systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                NavigationLink {
                    StudyView(initialTopic: selectedTopicName)
                } label: {
                    Label(String(localized: "Classic Flip Flashcards"), systemImage: "rectangle.stack")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.cardSubtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(18)
        }
    }

    /// Shown until the user has taken the placement test once; afterwards it lives on the Progress screen.
    private var placementPromptCard: some View {
        Button {
            showPlacementTest = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.accentSoft, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Check Your Level (1-min Test)"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(String(localized: "The game will skip words you already know."))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(14)
            .background(AppTheme.cardSubtle, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// One row summarizing progress; tapping opens stats, vocabulary tiers and achievements.
    private var progressLinkCard: some View {
        let unlocked = summary.badges.filter(\.unlocked).count
        return NavigationLink {
            LearnProgressView(summary: summary, vocabularyCount: progress.count)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.accentSoft, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Progress & achievements"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(verbatim: "\(summary.cefrLevel.rawValue) · \(summary.estimatedKnownWords) \(String(localized: "words")) · 🏅 \(unlocked)/\(summary.badges.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(14)
            .background(AppTheme.cardSubtle, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var streakAndLevelCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "flame.fill")
                        .font(.title3)
                        .foregroundStyle(summary.currentStreakDays > 0 ? .orange : AppTheme.textSecondary)
                        .frame(width: 40, height: 40)
                        .background(
                            (summary.currentStreakDays > 0 ? Color.orange.opacity(0.14) : AppTheme.cardSubtle),
                            in: Circle()
                        )
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(summary.currentStreakDays) \(String(localized: "day streak"))")
                            .font(.headline)
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("\(String(localized: "Best")): \(summary.longestStreakDays)d")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                Spacer()
                ShareCardButton(content: .progress(summary), title: String(localized: "Share"))
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .tint(AppTheme.accent)
                    .padding(.trailing, 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Lv. \(summary.level) · \(summary.levelTitle)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.accent)
                    Text("\(summary.totalXp) XP")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(String(localized: "Today's goal"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                    Text("\(summary.todayReviewed) / \(summary.dailyGoal)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(summary.todayReviewed >= summary.dailyGoal ? AppTheme.accent : AppTheme.textSecondary)
                }
                ProgressView(
                    value: Double(min(summary.todayReviewed, summary.dailyGoal)),
                    total: Double(max(1, summary.dailyGoal))
                )
                .tint(AppTheme.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(String(localized: "Level progress"))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                    Text("\(summary.xpInCurrentLevel) / \(summary.xpForNextLevel) XP")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.textSecondary)
                }
                ProgressView(
                    value: Double(summary.xpInCurrentLevel),
                    total: Double(summary.xpForNextLevel)
                )
                .tint(AppTheme.accent)
            }
        }
    }

    private func deckChip(title: String, source: GameDeckSource) -> some View {
        let active = selectedSource == source
        return Button {
            selectedSource = source
        } label: {
            Text(active ? "✓ \(title)" : title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(active ? AppTheme.onAccentSoft : AppTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    active ? AppTheme.accentSoft : AppTheme.cardSubtle,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

}

extension GameDeckSource: Identifiable {
    var id: String {
        switch self {
        case .smartMix: return "smart_mix"
        case .dueReviews: return "due_reviews"
        case .weakWords: return "weak_words"
        case .saved: return "saved"
        case .topic(let t): return "topic_\(t)"
        }
    }
}
