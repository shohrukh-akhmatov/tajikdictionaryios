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
            List {
                Section {
                    textRecognitionHeroCard
                }

                Section {
                    streakAndLevelCard
                }

                Section(String(localized: "Word Trainer")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedSource.title)
                                    .font(.headline)
                                Text(
                                    summary.dueNowCount > 0
                                        ? "\(summary.dueNowCount) \(String(localized: "words due for periodic review"))"
                                        : String(localized: "Frequency-ordered new words + smart reviews")
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if summary.dueNowCount > 0 {
                                Text("\(summary.dueNowCount)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.orange, in: Capsule())
                            }
                        }

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
                                    deckChip(title: item.topic.capitalized, source: .topic(item.topic))
                                }
                            }
                            .padding(.vertical, 2)
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
                                .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(String(localized: "Study Analytics")) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        analyticsTile(
                            value: "\(summary.estimatedKnownWords)",
                            label: String(localized: "Words known"),
                            icon: "text.book.closed.fill",
                            color: .blue
                        )
                        analyticsTile(
                            value: WordGameEngine.formatStudyDuration(seconds: summary.totalStudySeconds),
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
                            color: .green
                        )
                    }
                    .padding(.vertical, 4)

                    sevenDayChart
                }

                Section(String(localized: "Vocabulary Progress")) {
                    HStack(spacing: 12) {
                        vocabStat(count: summary.encounteredCount, label: String(localized: "Seen"), color: .blue)
                        vocabStat(count: summary.learningCount, label: String(localized: "Learning"), color: .orange)
                        vocabStat(count: summary.masteredCount, label: String(localized: "Mastered"), color: .green)
                    }
                    .padding(.vertical, 4)

                    ForEach(summary.tierBreakdown) { tier in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(tier.label)
                                    .font(.caption.weight(.medium))
                                Spacer()
                                Text("\(tier.knownCount) / \(tier.totalCount)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(
                                value: Double(tier.knownCount),
                                total: Double(max(1, tier.totalCount))
                            )
                        }
                    }

                    NavigationLink {
                        VocabularyListView()
                    } label: {
                        LabeledContent(
                            String(localized: "My Vocabulary"),
                            value: "\(progress.count)"
                        )
                    }
                }

                Section(String(localized: "Achievements")) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(summary.badges) { badge in
                            HStack(spacing: 10) {
                                Image(systemName: badge.systemImage)
                                    .font(.title3)
                                    .foregroundStyle(badge.unlocked ? Color.accentColor : .secondary)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(badge.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(badge.unlocked ? .primary : .secondary)
                                    Text(badge.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(
                                badge.unlocked ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .opacity(badge.unlocked ? 1.0 : 0.65)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.insetGrouped)
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

    private var textRecognitionHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: min(1.0, summary.textRecognitionPercent / 100.0))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(String(format: "%.0f%%", summary.textRecognitionPercent))
                            .font(.title3.bold())
                        Text(summary.cefrLevel.rawValue)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(width: 78, height: 78)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Everyday Tajik recognized"))
                        .font(.headline)
                    Text("\(summary.cefrLevel.rawValue) · \(summary.cefrLevel.title)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("\(summary.estimatedKnownWords) / \(summary.totalLexiconCount) \(String(localized: "words"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
    }

    private var sevenDayChart: some View {
        let maxCount = max(summary.dailyGoal, summary.recent7Days.map(\.wordsReviewed).max() ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Last 7 days"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(summary.recent7Days) { day in
                    let fraction = max(0.08, Double(day.wordsReviewed) / Double(max(1, maxCount)))
                    VStack(spacing: 4) {
                        Text("\(day.wordsReviewed)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .opacity(day.wordsReviewed > 0 ? 1 : 0)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                day.metGoal
                                    ? Color.green
                                    : (day.wordsReviewed > 0 ? Color.accentColor : Color.secondary.opacity(0.2))
                            )
                            .frame(height: 54 * fraction)
                        Text(day.shortLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 88, alignment: .bottom)
        }
        .padding(.vertical, 4)
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
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var streakAndLevelCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundStyle(summary.currentStreakDays > 0 ? .orange : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(summary.currentStreakDays) \(String(localized: "day streak"))")
                            .font(.headline)
                        Text("\(String(localized: "Best")): \(summary.longestStreakDays)d")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Lv. \(summary.level) · \(summary.levelTitle)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                    Text("\(summary.totalXp) XP")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(String(localized: "Today's goal"))
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text("\(summary.todayReviewed) / \(summary.dailyGoal)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(summary.todayReviewed >= summary.dailyGoal ? .green : .secondary)
                }
                ProgressView(
                    value: Double(min(summary.todayReviewed, summary.dailyGoal)),
                    total: Double(max(1, summary.dailyGoal))
                )
                .tint(summary.todayReviewed >= summary.dailyGoal ? .green : Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(String(localized: "Level progress"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(summary.xpInCurrentLevel) / \(summary.xpForNextLevel) XP")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(
                    value: Double(summary.xpInCurrentLevel),
                    total: Double(summary.xpForNextLevel)
                )
            }
        }
        .padding(.vertical, 6)
    }

    private func deckChip(title: String, source: GameDeckSource) -> some View {
        let active = selectedSource == source
        return Button {
            selectedSource = source
        } label: {
            Text(active ? "✓ \(title)" : title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    active ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12),
                    in: Capsule()
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
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
