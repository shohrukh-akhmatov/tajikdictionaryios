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

    init(deepLinkEntryId: Binding<Int64?> = .constant(nil)) {
        _deepLinkEntryId = deepLinkEntryId
    }

    var body: some View {
        @Bindable var settings = settings
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    ModeSwitcher(mode: $settings.mode)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(
                            settings.mode == .tjRu
                                ? String(localized: "Search Tajik or Russian…")
                                : String(localized: "Search Tajik or English…"),
                            text: $query
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)

                        if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    TajikLettersBar { letter in
                        query += letter
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

                Divider()

                contentView
            }
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
            homeList
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
            List {
                if outcome.matchType != .direct {
                    Section {
                        Text(
                            outcome.matchType == .stem
                                ? "Showing base forms for “\(trimmed)”"
                                : String(localized: "Showing closest spelling matches")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                ForEach(outcome.results) { row in
                    NavigationLink(value: row.id) {
                        WordRowView(
                            language: row.language,
                            headword: row.headword,
                            pos: row.pos,
                            preview: row.preview
                        )
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var homeList: some View {
        List {
            if let wotd = viewModel?.wordOfTheDay {
                Section {
                    NavigationLink(value: wotd.entry.id) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(String(localized: "Word of the day"), systemImage: "sparkles")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tint)
                                Spacer()
                                LanguageTag(language: wotd.entry.language)
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(wotd.entry.headword)
                                    .font(.title2.bold())
                                if let pos = wotd.entry.pos {
                                    Text(pos.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if !wotd.preview.isEmpty {
                                Text(wotd.preview)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if let topics = viewModel?.topics, !topics.isEmpty {
                Section(String(localized: "Topics")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(topics) { item in
                                NavigationLink(value: item) {
                                    Text("\(item.topic) (\(item.count))")
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(.tint.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if !recent.isEmpty {
                Section {
                    ForEach(recent.prefix(15)) { item in
                        NavigationLink(value: item.entryId) {
                            WordRowView(
                                language: item.language,
                                headword: item.headword,
                                pos: nil,
                                preview: item.preview
                            )
                        }
                    }
                } header: {
                    HStack {
                        Text(String(localized: "Recent searches"))
                        Spacer()
                        Button(String(localized: "Clear")) {
                            clearHistory()
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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
