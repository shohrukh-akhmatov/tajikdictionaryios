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
                    wordTrainerCard

                    AppCard {
                        textRecognitionHeroCard
                            .padding(16)
                    }

                    AppCard {
                        streakAndLevelCard
                            .padding(16)
                    }

                    AppCard {
                        studyAnalyticsCard
                            .padding(16)
                    }

                    AppCard {
                        vocabularyProgressCard
                            .padding(16)
                    }

                    SectionHeader(title: String(localized: "Achievements"))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(summary.badges) { badge in
                            AppCard(cornerRadius: 16) {
                                HStack(spacing: 10) {
                                    Image(systemName: badge.systemImage)
                                        .font(.subheadline)
                                        .foregroundStyle(badge.unlocked ? AppTheme.accent : AppTheme.textSecondary)
                                        .frame(width: 34, height: 34)
                                        .background(
                                            badge.unlocked ? AppTheme.accentSoft : AppTheme.cardSubtle,
                                            in: Circle()
                                        )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(badge.title)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(badge.unlocked ? AppTheme.textPrimary : AppTheme.textSecondary)
                                        Text(badge.subtitle)
                                            .font(.caption2)
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                    if badge.unlocked {
                                        ShareCardButton(content: .badge(badge, summary: summary), title: String(localized: "Share"))
                                            .labelStyle(.iconOnly)
                                            .buttonStyle(.borderless)
                                            .font(.caption)
                                            .tint(AppTheme.accent)
                                    }
                                }
                                .padding(12)
                            }
                            .opacity(badge.unlocked ? 1.0 : 0.6)
                        }
                    }
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

    private var textRecognitionHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(AppTheme.cardSubtle, lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: min(1.0, summary.textRecognitionPercent / 100.0))
                        .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: summary.textRecognitionPercent)
                    VStack(spacing: 0) {
                        Text(String(format: "%.0f%%", summary.textRecognitionPercent))
                            .font(.title3.bold())
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(summary.cefrLevel.rawValue)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .frame(width: 82, height: 82)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Everyday Tajik recognized"))
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("\(summary.cefrLevel.rawValue) · \(summary.cefrLevel.title)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text("\(summary.estimatedKnownWords) / \(summary.totalLexiconCount) \(String(localized: "words"))")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }

            Button {
                showPlacementTest = true
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                    Text(
                        settings.hasCompletedPlacement
                            ? String(localized: "Retake Level Placement Test")
                            : String(localized: "Check Your Level (1-min Test)")
                    )
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var studyAnalyticsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Study Analytics"))
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                analyticsTile(
                    value: "\(summary.estimatedKnownWords)",
                    label: String(localized: "Words known"),
                    icon: "text.book.closed.fill",
                    color: AppTheme.accent
                )
                analyticsTile(
                    value: StudyDurationFormatter.format(seconds: summary.totalStudySeconds),
                    label: String(localized: "Time studied"),
                    icon: "clock.fill",
                    color: .purple
                )
                analyticsTile(
                    value: "\(summary.activeDaysCount)",
                    label: String(localized: "Active days"),
                    icon: "calendar",
                    color: .orange
                )
                analyticsTile(
                    value: "\(summary.overallAccuracyPercent)%",
                    label: "\(summary.totalReviews) \(String(localized: "reviews"))",
                    icon: "target",
                    color: AppTheme.accent
                )
            }

            sevenDayChart
        }
    }

    private var vocabularyProgressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "Vocabulary Progress"))
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                NavigationLink {
                    VocabularyListView()
                } label: {
                    HStack(spacing: 4) {
                        Text("\(String(localized: "My Vocabulary")) (\(progress.count))")
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                }
            }

            HStack(spacing: 10) {
                vocabStat(count: summary.encounteredCount, label: String(localized: "Seen"), color: .blue)
                vocabStat(count: summary.learningCount, label: String(localized: "Learning"), color: .orange)
                vocabStat(count: summary.masteredCount, label: String(localized: "Mastered"), color: AppTheme.accent)
            }

            ForEach(summary.tierBreakdown) { tier in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(tier.label)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Text("\(tier.knownCount) / \(tier.totalCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    ProgressView(
                        value: Double(tier.knownCount),
                        total: Double(max(1, tier.totalCount))
                    )
                    .tint(AppTheme.accent)
                }
            }
        }
    }

    private var sevenDayChart: some View {
        let maxCount = max(summary.dailyGoal, summary.recent7Days.map(\.wordsReviewed).max() ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Last 7 days"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(summary.recent7Days) { day in
                    let fraction = max(0.08, Double(day.wordsReviewed) / Double(max(1, maxCount)))
                    VStack(spacing: 4) {
                        Text("\(day.wordsReviewed)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(AppTheme.textSecondary)
                            .opacity(day.wordsReviewed > 0 ? 1 : 0)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                day.metGoal
                                    ? AppTheme.accent
                                    : (day.wordsReviewed > 0 ? AppTheme.accent.opacity(0.55) : AppTheme.cardSubtle)
                            )
                            .frame(width: 22, height: 54 * fraction)
                        Text(day.shortLabel)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 88, alignment: .bottom)
        }
    }

    private func analyticsTile(value: String, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(AppTheme.textPrimary)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    private func vocabStat(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
