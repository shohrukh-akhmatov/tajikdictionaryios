import SwiftData
import SwiftUI

struct SearchView: View {
    @Environment(\.dictionaryRepository) private var repository
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings

    @Binding var deepLinkEntryId: Int64?
    @Query(sort: \HistoryItem.viewedAt, order: .reverse) private var recent: [HistoryItem]
    @State private var viewModel: SearchViewModel?
    @State private var query: String = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var navigationPath = NavigationPath()
    @State private var speaker = SpeechSpeaker()

    init(deepLinkEntryId: Binding<Int64?> = .constant(nil)) {
        _deepLinkEntryId = deepLinkEntryId
    }

    var body: some View {
        @Bindable var settings = settings
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    ModeSwitcher(mode: $settings.mode)

                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppTheme.accent)
                        TextField(
                            settings.mode == .tjRu
                                ? String(localized: "Search Tajik or Russian…")
                                : String(localized: "Search Tajik or English…"),
                            text: $query
                        )
                        .foregroundStyle(AppTheme.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)

                        if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(AppTheme.cardSubtle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                query.isEmpty ? AppTheme.border.opacity(0.8) : AppTheme.accent.opacity(0.45),
                                lineWidth: 1
                            )
                    )

                    TajikLettersBar { letter in
                        query += letter
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.card)

                Divider()

                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.background)
                    .dismissesKeyboardOnTap()
            }
            .background(AppTheme.background)
            .navigationTitle(String(localized: "Dictionary"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Int64.self) { entryId in
                EntryDetailView(entryId: entryId)
            }
            .navigationDestination(for: TopicCount.self) { topicItem in
                TopicEntriesView(topic: topicItem.topic)
            }
        }
        .task {
            if viewModel == nil {
                let vm = SearchViewModel(repository: repository)
                viewModel = vm
                await vm.loadTopics()
                await vm.refreshWordOfTheDay(mode: settings.mode)
            }
            if let entryId = deepLinkEntryId {
                navigationPath.append(entryId)
                deepLinkEntryId = nil
            }
        }
        .onDisappear {
            speaker.stop()
        }
        .onChange(of: deepLinkEntryId) { _, entryId in
            guard let entryId else { return }
            navigationPath.append(entryId)
            deepLinkEntryId = nil
        }
        .onChange(of: query) { _, newValue in
            triggerSearch(newValue, mode: settings.mode)
        }
        .onChange(of: settings.mode) { _, newMode in
            triggerSearch(query, mode: newMode)
            Task { await viewModel?.refreshWordOfTheDay(mode: newMode) }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            homeScrollView
        } else if let suggested = viewModel?.outcome.suggestedMode {
            ContentUnavailableView {
                Label(String(localized: "Different language detected"), systemImage: "character.bubble")
            } description: {
                Text("No matches in \(settings.mode.title). Switch to \(suggested.title)?")
            } actions: {
                Button("Switch to \(suggested.title)") {
                    settings.mode = suggested
                }
                .buttonStyle(.borderedProminent)
            }
        } else if let outcome = viewModel?.outcome, outcome.results.isEmpty {
            ContentUnavailableView.search(text: trimmed)
        } else if let outcome = viewModel?.outcome {
            ScrollView {
                VStack(spacing: 12) {
                    if outcome.matchType != .direct {
                        Group {
                            switch outcome.matchType {
                            case .stem:
                                Text("Showing base forms for “\(trimmed)”")
                            case .words:
                                Text(String(localized: "Phrase not found — showing each word separately"))
                            case .fuzzy, .direct:
                                Text(String(localized: "Showing closest spelling matches"))
                            }
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.onAccentSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppTheme.accentSoft.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    AppCard {
                        ForEach(Array(outcome.results.enumerated()), id: \.element.id) { idx, row in
                            NavigationLink(value: row.id) {
                                HStack {
                                    WordRowView(
                                        language: row.language,
                                        headword: row.headword,
                                        pos: row.pos,
                                        preview: row.preview
                                    )
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)

                            if idx < outcome.results.count - 1 {
                                Divider()
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private var homeScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let wotd = viewModel?.wordOfTheDay {
                    wordOfTheDayCard(wotd)
                }

                if let topics = viewModel?.topics, !topics.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: String(localized: "Topics"))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(topics) { item in
                                    NavigationLink(value: item) {
                                        HStack(spacing: 8) {
                                            Text(TopicLocalization.displayName(for: item.topic))
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(AppTheme.textPrimary)
                                            Text("\(item.count)")
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(AppTheme.onAccentSoft)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 9)
                                        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(AppTheme.border.opacity(0.7), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                if !recent.isEmpty {
                    let items = Array(recent.prefix(15))
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(
                            title: String(localized: "Recent searches"),
                            actionTitle: String(localized: "Clear")
                        ) {
                            clearHistory()
                        }

                        AppCard {
                            ForEach(Array(items.enumerated()), id: \.element.entryId) { idx, item in
                                NavigationLink(value: item.entryId) {
                                    HStack {
                                        WordRowView(
                                            language: item.language,
                                            headword: item.headword,
                                            pos: nil,
                                            preview: item.preview
                                        )
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)

                                if idx < items.count - 1 {
                                    Divider()
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    private func wordOfTheDayCard(_ wotd: (entry: Entry, preview: String)) -> some View {
        let canSpeak = speaker.canSpeak(wotd.entry.language) || (!wotd.preview.isEmpty && speaker.canSpeak(settings.mode.partner))

        return AppCard(cornerRadius: 20, borderColor: AppTheme.accent.opacity(0.25)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 24, height: 24)
                            .background(AppTheme.accentSoft, in: Circle())
                        Text(String(localized: "Word of the day"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    Spacer()
                    LanguageTag(language: wotd.entry.language)
                }

                HStack(alignment: .center) {
                    NavigationLink(value: wotd.entry.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .center, spacing: 8) {
                                Text(wotd.entry.headword)
                                    .font(.title2.bold())
                                    .foregroundStyle(AppTheme.textPrimary)
                                if let pos = wotd.entry.pos {
                                    PosBadge(label: pos.label)
                                }
                            }
                            if wotd.entry.language == .tajik {
                                let latin = TajikTransliterator.toLatin(wotd.entry.headword)
                                if !latin.isEmpty {
                                    Text("/\(latin)/")
                                        .font(.subheadline.italic())
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    if canSpeak {
                        Button {
                            if speaker.canSpeak(wotd.entry.language) {
                                speaker.speak(wotd.entry.headword, language: wotd.entry.language, rate: settings.avSpeechRate)
                            } else if !wotd.preview.isEmpty {
                                let firstMeaning = wotd.preview.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? wotd.preview
                                speaker.speak(firstMeaning, language: settings.mode.partner, rate: settings.avSpeechRate)
                            }
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 40, height: 40)
                                .background(AppTheme.accentSoft, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Listen"))
                    }
                }

                if !wotd.preview.isEmpty {
                    Divider()
                    NavigationLink(value: wotd.entry.id) {
                        Text(wotd.preview)
                            .font(.body)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
        }
    }

    private func triggerSearch(_ text: String, mode: DictionaryMode) {
        searchTask?.cancel()
        guard let vm = viewModel else { return }
        vm.query = text
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            vm.outcome = .empty
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await vm.runSearchNow(mode: mode)
        }
    }

    private func clearHistory() {
        for item in recent {
            modelContext.delete(item)
        }
    }
}
