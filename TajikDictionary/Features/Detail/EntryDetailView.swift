import SwiftData
import SwiftUI

struct EntryDetailView: View {
    let entryId: Int64

    @Environment(\.dictionaryRepository) private var repository
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings

    @Query private var favorites: [FavoriteItem]
    @Query private var progressItems: [FlashcardProgress]
    @State private var detail: EntryDetail?
    @State private var isLoading = true
    @State private var speaker = SpeechSpeaker()
    @State private var copied = false

    init(entryId: Int64) {
        self.entryId = entryId
        _favorites = Query(filter: #Predicate<FavoriteItem> { $0.entryId == entryId })
        _progressItems = Query(filter: #Predicate<FlashcardProgress> { $0.entryId == entryId })
    }

    private var isFavorite: Bool { !favorites.isEmpty }
    private var cardProgress: FlashcardProgress? { progressItems.first }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.background)
            } else if let detail {
                detailScrollView(detail)
            } else {
                ContentUnavailableView(String(localized: "Word not found"), systemImage: "book.closed")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.background)
            }
        }
        // The tab's pinned banner switches to the word-detail ad unit while this screen is shown.
        .onAppear { AdsManager.shared.entryScreensVisible += 1 }
        .onDisappear { AdsManager.shared.entryScreensVisible -= 1 }
        .navigationTitle(detail?.entry.headword ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let detail {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        toggleFavorite(detail)
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? AppTheme.accent : AppTheme.textSecondary)
                    }
                    .accessibilityLabel(String(localized: "Favorite"))
                }
            }
        }
        .task(id: entryId) {
            isLoading = true
            let loaded = try? await repository.detail(id: entryId, mode: settings.mode)
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

    private struct SenseGroup: Identifiable {
        var id: Int { senseNumber }
        let senseNumber: Int
        let translations: [Translation]
    }

    @ViewBuilder
    private func detailScrollView(_ detail: EntryDetail) -> some View {
        let preferred = settings.mode.translationTarget(for: detail.entry.language)
        let allTranslations = detail.translations.values.flatMap { $0 }
        let groupedByPos = Dictionary(grouping: allTranslations, by: \.position)
        let senseGroups: [SenseGroup] = groupedByPos.keys.sorted().enumerated().map { idx, posKey in
            let ordered = (groupedByPos[posKey] ?? []).sorted { lhs, rhs in
                if lhs.language == preferred, rhs.language != preferred { return true }
                if rhs.language == preferred, lhs.language != preferred { return false }
                return lhs.language.rawValue < rhs.language.rawValue
            }
            return SenseGroup(senseNumber: idx + 1, translations: ordered)
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Hero Word Card
                AppCard(cornerRadius: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            LanguageTag(language: detail.entry.language)
                            if let pos = detail.entry.pos {
                                PosBadge(label: pos.label)
                            }
                            if let topic = detail.entry.topic {
                                NavigationLink {
                                    TopicEntriesView(topic: topic)
                                } label: {
                                    Text(TopicLocalization.displayName(for: topic))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(AppTheme.onAccentSoft)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text(detail.entry.headword)
                            .font(.system(size: 34 * settings.fontScale.multiplier, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .textSelection(.enabled)

                        if detail.entry.language == .tajik {
                            let latin = TajikTransliterator.toLatin(detail.entry.headword)
                            if !latin.isEmpty {
                                Text("/\(latin)/")
                                    .font(.headline.italic())
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }

                        HStack(spacing: 8) {
                            if speaker.canSpeak(detail.entry.language) {
                                Button {
                                    speaker.speak(detail.entry.headword, language: detail.entry.language, rate: settings.avSpeechRate)
                                } label: {
                                    Label(String(localized: "Listen"), systemImage: "speaker.wave.2.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.onAccentSoft)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                UIPasteboard.general.string = shareText(for: detail)
                                copied = true
                            } label: {
                                Label(
                                    copied ? String(localized: "Copied") : String(localized: "Copy"),
                                    systemImage: copied ? "checkmark" : "doc.on.doc"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppTheme.cardSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            ShareLink(item: shareText(for: detail)) {
                                Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(AppTheme.cardSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                }

                // Homographs / Other parts of speech (e.g. соҳибӣ n. vs adj.)
                if !detail.homographs.isEmpty {
                    SectionHeader(title: String(localized: "Other meanings & parts of speech"))
                    AppCard(backgroundColor: AppTheme.cardSubtle) {
                        ForEach(Array(detail.homographs.enumerated()), id: \.element.id) { idx, item in
                            NavigationLink(value: item.id) {
                                HStack(spacing: 10) {
                                    if let pos = item.pos {
                                        PosBadge(label: pos.label)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.headword)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                        if !item.preview.isEmpty {
                                            Text(item.preview)
                                                .font(.subheadline)
                                                .foregroundStyle(AppTheme.textSecondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)

                            if idx < detail.homographs.count - 1 {
                                Divider().padding(.horizontal, 16)
                            }
                        }
                    }
                }

                // Sense-Grouped Translations
                if !senseGroups.isEmpty {
                    AppCard {
                        ForEach(Array(senseGroups.enumerated()), id: \.element.id) { groupIdx, group in
                            VStack(alignment: .leading, spacing: 0) {
                                if senseGroups.count > 1 {
                                    HStack(spacing: 8) {
                                        Text("\(group.senseNumber)")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.white)
                                            .frame(width: 20, height: 20)
                                            .background(AppTheme.accent, in: Circle())
                                        Text("\(String(localized: "Sense")) \(group.senseNumber)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(AppTheme.cardSubtle.opacity(0.7))
                                }

                                ForEach(Array(group.translations.enumerated()), id: \.element.id) { idx, tr in
                                    HStack(spacing: 12) {
                                        NavigationLink(value: tr.entryId) {
                                            HStack(spacing: 12) {
                                                LanguageTag(language: tr.language)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    HStack(spacing: 6) {
                                                        Text(tr.headword)
                                                            .font(.body.weight(.medium))
                                                            .foregroundStyle(AppTheme.textPrimary)
                                                        if let pos = tr.pos {
                                                            PosBadge(label: pos.label)
                                                        }
                                                    }
                                                    if tr.language == .tajik {
                                                        let latin = TajikTransliterator.toLatin(tr.headword)
                                                        if !latin.isEmpty {
                                                            Text("/\(latin)/")
                                                                .font(.caption.italic())
                                                                .foregroundStyle(AppTheme.accent)
                                                        }
                                                    }
                                                    if let note = tr.note {
                                                        Text("(\(note))")
                                                            .font(.caption)
                                                            .foregroundStyle(AppTheme.textSecondary)
                                                    }
                                                }
                                                Spacer(minLength: 0)
                                            }
                                        }
                                        .buttonStyle(.plain)

                                        if speaker.canSpeak(tr.language) {
                                            Button {
                                                speaker.speak(tr.headword, language: tr.language, rate: settings.avSpeechRate)
                                            } label: {
                                                Image(systemName: "speaker.wave.2.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(AppTheme.accent)
                                                    .frame(width: 30, height: 30)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel(String(localized: "Listen"))
                                        }

                                        NavigationLink(value: tr.entryId) {
                                            Image(systemName: "chevron.right")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)

                                    if idx < group.translations.count - 1 {
                                        Divider().padding(.horizontal, 16)
                                    }
                                }
                            }

                            if groupIdx < senseGroups.count - 1 {
                                Divider()
                            }
                        }
                    }
                }

                // Examples
                if !detail.examples.isEmpty {
                    SectionHeader(title: String(localized: "Examples"))
                    ForEach(detail.examples) { ex in
                        AppCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ex.tg)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                        let exLatin = TajikTransliterator.toLatin(ex.tg)
                                        if !exLatin.isEmpty {
                                            Text("/\(exLatin)/")
                                                .font(.caption.italic())
                                                .foregroundStyle(AppTheme.accent)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    if speaker.canSpeak(.tajik) {
                                        Button {
                                            speaker.speak(ex.tg, language: .tajik, rate: settings.avSpeechRate)
                                        } label: {
                                            Image(systemName: "speaker.wave.2.fill")
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.accent)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                if let ru = ex.ru {
                                    exampleLine(language: .russian, text: ru)
                                }
                                if let en = ex.en {
                                    exampleLine(language: .english, text: en)
                                }
                            }
                            .padding(16)
                        }
                    }
                }

                // Synonyms
                if !detail.synonyms.isEmpty {
                    SectionHeader(title: String(localized: "Synonyms"))
                    FlowLayout(spacing: 8) {
                        ForEach(detail.synonyms) { item in
                            relatedChip(item)
                        }
                    }
                }

                // Related words
                if !detail.relatedWords.isEmpty {
                    SectionHeader(title: String(localized: "Related words"))
                    FlowLayout(spacing: 8) {
                        ForEach(detail.relatedWords) { item in
                            relatedChip(item)
                        }
                    }
                }

                // Integrated Word Trainer Learning Card
                if detail.entry.language == .tajik {
                    let isMastered = cardProgress?.isKnownSkipped == true || (cardProgress?.masteryStage ?? 0) >= 4
                    let stage = isMastered ? 4 : min(4, max(0, cardProgress?.masteryStage ?? 0))

                    AppCard(borderColor: AppTheme.accent.opacity(0.25)) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                HStack(spacing: 8) {
                                    Image(systemName: "graduationcap.fill")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.accent)
                                        .frame(width: 28, height: 28)
                                        .background(AppTheme.accentSoft, in: Circle())
                                    Text(String(localized: "Word Trainer"))
                                        .font(.headline)
                                        .foregroundStyle(AppTheme.textPrimary)
                                }
                                Spacer()
                                Text(learningStatusLabel(for: cardProgress))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(isMastered ? AppTheme.onAccentSoft : AppTheme.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(isMastered ? AppTheme.accentSoft : AppTheme.cardSubtle, in: Capsule())
                            }

                            HStack(spacing: 6) {
                                ForEach(1...4, id: \.self) { step in
                                    Capsule()
                                        .fill(step <= stage ? AppTheme.accent : AppTheme.cardSubtle)
                                        .frame(height: 6)
                                }
                            }

                            HStack(spacing: 8) {
                                Button {
                                    queueForPractice(detail)
                                } label: {
                                    Label(
                                        cardProgress == nil
                                            ? String(localized: "Add to Learning Queue")
                                            : String(localized: "Practice Again"),
                                        systemImage: "plus.circle"
                                    )
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)

                                if !isMastered {
                                    Button {
                                        markKnown(detail)
                                    } label: {
                                        Label(String(localized: "Mark as Known"), systemImage: "checkmark.circle")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .padding(16)
        }
        .background(AppTheme.background)
    }

    @ViewBuilder
    private func exampleLine(language: Language, text: String) -> some View {
        HStack(spacing: 8) {
            LanguageTag(language: language)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if speaker.canSpeak(language) {
                Button {
                    speaker.speak(text, language: language, rate: settings.avSpeechRate)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func relatedChip(_ item: SearchResult) -> some View {
        NavigationLink(value: item.id) {
            HStack(spacing: 6) {
                Text(item.headword)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                if let pos = item.pos {
                    Text(pos.label)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.border.opacity(0.7), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

    private func learningStatusLabel(for item: FlashcardProgress?) -> String {
        guard let item else { return String(localized: "Not studied yet") }
        if item.isKnownSkipped || item.masteryStage >= 4 {
            return String(localized: "Mastered / Known")
        }
        return "\(String(localized: "Learning")) · \(String(localized: "Stage")) \(item.masteryStage)/4"
    }

    private func queueForPractice(_ detail: EntryDetail) {
        let now = Date.now
        let preview = previewString(for: detail)
        if let existing = cardProgress {
            existing.isKnownSkipped = false
            existing.masteryStage = 0
            existing.stabilityDays = 0.25
            existing.nextReviewAt = now
            existing.lastReviewedAt = existing.lastReviewedAt ?? now
            existing.preview = preview
        } else {
            modelContext.insert(FlashcardProgress(
                entryId: detail.entry.id,
                lang: detail.entry.language.rawValue,
                headword: detail.entry.headword,
                preview: preview,
                repetitions: 0,
                intervalDays: 0,
                easeFactor: 2.5,
                nextReviewAt: now,
                masteryStage: 0,
                stabilityDays: 0.25,
                lapses: 0,
                lastReviewedAt: now,
                isKnownSkipped: false
            ))
        }
        try? modelContext.save()
    }

    private func markKnown(_ detail: EntryDetail) {
        let now = Date.now
        let future = now.addingTimeInterval(180 * WordGameEngine.daySeconds)
        let preview = previewString(for: detail)
        if let existing = cardProgress {
            existing.isKnownSkipped = true
            existing.masteryStage = 4
            existing.stabilityDays = 180
            existing.nextReviewAt = future
            existing.lastReviewedAt = now
            existing.preview = preview
        } else {
            modelContext.insert(FlashcardProgress(
                entryId: detail.entry.id,
                lang: detail.entry.language.rawValue,
                headword: detail.entry.headword,
                preview: preview,
                repetitions: 1,
                intervalDays: 180,
                easeFactor: 2.5,
                nextReviewAt: future,
                masteryStage: 4,
                stabilityDays: 180,
                lapses: 0,
                lastReviewedAt: now,
                isKnownSkipped: true
            ))
        }
        try? modelContext.save()
    }
}
