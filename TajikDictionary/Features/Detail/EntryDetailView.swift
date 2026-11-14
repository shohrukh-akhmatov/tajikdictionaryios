import AVFoundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class SpeechSpeaker {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, localeIdentifier: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: localeIdentifier)
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

struct EntryDetailView: View {
    let entryId: Int64

    @Environment(\.dictionaryRepository) private var repository
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings

    @Query private var favorites: [FavoriteItem]
    @State private var detail: EntryDetail?
    @State private var isLoading = true
    @State private var speaker = SpeechSpeaker()
    @State private var copied = false

    init(entryId: Int64) {
        self.entryId = entryId
        _favorites = Query(filter: #Predicate<FavoriteItem> { $0.entryId == entryId })
    }

    private var isFavorite: Bool { !favorites.isEmpty }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let detail {
                detailList(detail)
            } else {
                ContentUnavailableView(String(localized: "Word not found"), systemImage: "book.closed")
            }
        }
        .navigationTitle(detail?.entry.headword ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let detail {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        toggleFavorite(detail)
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? Color.accentColor : .secondary)
                    }
                    .accessibilityLabel(String(localized: "Favorite"))
                }
            }
        }
        .task(id: entryId) {
            isLoading = true
            let loaded = try? await repository.detail(id: entryId)
            detail = loaded
            isLoading = false
            if let loaded {
                recordHistory(loaded)
            }
        }
        .onDisappear {
            speaker.stop()
        }
    }

    @ViewBuilder
    private func detailList(_ detail: EntryDetail) -> some View {
        let preferred = settings.mode.translationTarget(for: detail.entry.language)
        let orderedGroups = detail.translations.sorted { lhs, rhs in
            if lhs.key == preferred { return true }
            if rhs.key == preferred { return false }
            return lhs.key.rawValue < rhs.key.rawValue
        }

        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        LanguageTag(language: detail.entry.language)
                        if let pos = detail.entry.pos {
                            Text(pos.label)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let topic = detail.entry.topic {
                            Text("· \(topic)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(detail.entry.headword)
                        .font(.largeTitle.bold())
                        .textSelection(.enabled)

                    HStack(spacing: 10) {
                        if let locale = detail.entry.language.speechLocaleIdentifier {
                            Button {
                                speaker.speak(detail.entry.headword, localeIdentifier: locale)
                            } label: {
                                Label(String(localized: "Listen"), systemImage: "speaker.wave.2.fill")
                            }
                            .buttonStyle(.bordered)
                        }

                        Button {
                            UIPasteboard.general.string = shareText(for: detail)
                            copied = true
                        } label: {
                            Label(
                                copied ? String(localized: "Copied") : String(localized: "Copy"),
                                systemImage: copied ? "checkmark" : "doc.on.doc"
                            )
                        }
                        .buttonStyle(.bordered)

                        ShareLink(item: shareText(for: detail)) {
                            Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(.caption)
                }
                .padding(.vertical, 4)
            }

            ForEach(orderedGroups, id: \.key) { lang, items in
                Section(lang.displayName) {
                    ForEach(items) { tr in
                        NavigationLink(value: tr.entryId) {
                            HStack(spacing: 10) {
                                LanguageTag(language: tr.language)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tr.headword)
                                        .font(.body.weight(.medium))
                                    if let note = tr.note {
                                        Text("(\(note))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if !detail.examples.isEmpty {
                Section(String(localized: "Examples")) {
                    ForEach(detail.examples) { ex in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ex.tg)
                                .font(.body.weight(.semibold))
                            if let ru = ex.ru {
                                Text(ru).font(.subheadline).foregroundStyle(.secondary)
                            }
                            if let en = ex.en {
                                Text(en).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func previewString(for detail: EntryDetail) -> String {
        let target = settings.mode.translationTarget(for: detail.entry.language)
        return (detail.translations[target] ?? [])
            .prefix(4)
            .map(\.headword)
            .joined(separator: ", ")
    }

    private func toggleFavorite(_ detail: EntryDetail) {
        if let existing = favorites.first {
            modelContext.delete(existing)
        } else {
            let item = FavoriteItem(
                entryId: detail.entry.id,
                lang: detail.entry.language.rawValue,
                headword: detail.entry.headword,
                preview: previewString(for: detail)
            )
            modelContext.insert(item)
        }
    }

    private func recordHistory(_ detail: EntryDetail) {
        let id = detail.entry.id
        let descriptor = FetchDescriptor<HistoryItem>(predicate: #Predicate { $0.entryId == id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.viewedAt = .now
            existing.preview = previewString(for: detail)
        } else {
            modelContext.insert(HistoryItem(
                entryId: id,
                lang: detail.entry.language.rawValue,
                headword: detail.entry.headword,
                preview: previewString(for: detail)
            ))
        }

        // Keep at most HistoryItem.maxItems
        let allDesc = FetchDescriptor<HistoryItem>(sortBy: [SortDescriptor(\.viewedAt, order: .reverse)])
        if let all = try? modelContext.fetch(allDesc), all.count > HistoryItem.maxItems {
            for extra in all.dropFirst(HistoryItem.maxItems) {
                modelContext.delete(extra)
            }
        }
    }

    private func shareText(for detail: EntryDetail) -> String {
        var lines = ["\(detail.entry.headword) [\(detail.entry.language.tag)]"]
        for (lang, list) in detail.translations.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            lines.append("\(lang.tag): \(list.map(\.headword).joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }
}
