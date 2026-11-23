import Foundation

/// Thread-safe read-only repository over the bundled `dictionary.sqlite`.
actor DictionaryRepository {
    private let db: SQLiteDatabase

    init(databaseURL: URL? = Bundle.main.url(forResource: "dictionary", withExtension: "sqlite")) throws {
        guard let url = databaseURL else {
            throw SQLiteError.openFailed("dictionary.sqlite missing from app bundle")
        }
        self.db = try SQLiteDatabase(path: url.path)
    }

    /// Correlated subquery yielding a short `", "`-joined translation preview for `entry`.
    /// Consumes exactly one `?` binding: the partner language code.
    /// - By default the preview language is the partner for Tajik entries and Tajik for RU/EN entries;
    ///   `fixedPartner` always uses the bound language.
    /// - Translations with the same spelling (homograph targets like two "ташаккур" entries)
    ///   are collapsed so previews never read "ташаккур, раҳмат, ташаккур".
    static func previewColumn(entry alias: String, limit: Int, fixedPartner: Bool = false) -> String {
        let langCondition = fixedPartner
            ? "?"
            : "CASE WHEN \(alias).lang = 'tg' THEN ? ELSE 'tg' END"
        return """
        (SELECT group_concat(h, ', ') FROM (
            SELECT pe.headword AS h, MIN(pt.position) AS p, MIN(pt.id) AS first_id
            FROM translations pt JOIN entries pe ON pe.id = pt.to_id
            WHERE pt.from_id = \(alias).id AND pe.lang = \(langCondition)
            GROUP BY pe.headword
            ORDER BY p, first_id
            LIMIT \(limit)))
        """
    }

    func search(query rawQuery: String, mode: DictionaryMode, limit: Int = 50) throws -> SearchOutcome {
        let key = TextNormalizer.searchKey(rawQuery)
        if key.isEmpty { return .empty }

        let candidates = LanguageDetector.candidates(for: rawQuery)
        let languages = candidates.intersection(mode.languages)
        if languages.isEmpty {
            let suggestion = DictionaryMode.allCases.first { !candidates.intersection($0.languages).isEmpty }
            return SearchOutcome(query: rawQuery, results: [], searchedLanguages: [], suggestedMode: suggestion)
        }

        let direct = try prefixSearch(key: key, languages: languages, mode: mode, limit: limit)
        let hasExactDirect = direct.contains { TextNormalizer.searchKey($0.headword) == key }
        if !direct.isEmpty, hasExactDirect {
            return SearchOutcome(query: rawQuery, results: direct, searchedLanguages: languages, suggestedMode: nil, matchType: .direct)
        }

        // Phase 1 fallback 1: morphological stem hints (exact lemma match)
        // Also checked when `direct` only had longer prefix hits (e.g. "китобҳо" vs "китобхона").
        let stems = WordStemmer.candidateStems(for: key, languages: languages)
            .filter { !direct.isEmpty ? $0.count >= 3 : true }
        if !stems.isEmpty {
            let stemResults = try exactMatches(keys: stems, languages: languages, mode: mode, limit: limit)
            if !stemResults.isEmpty {
                let stemIds = Set(stemResults.map(\.id))
                let combined = Array((stemResults + direct.filter { !stemIds.contains($0.id) }).prefix(limit))
                return SearchOutcome(
                    query: rawQuery,
                    results: combined,
                    searchedLanguages: languages,
                    suggestedMode: nil,
                    matchType: .stem
                )
            }
        }
        if !direct.isEmpty {
            // If every prefix hit is a much longer word (4+ extra chars) and a 1-edit typo match exists
            // (e.g. "салам" vs prefix "саламандра" when user meant "салом"), surface the close typo match.
            let onlyLongPrefixHits = key.count >= 5 && direct.allSatisfy {
                TextNormalizer.searchKey($0.headword).count >= key.count + 4
            }
            if onlyLongPrefixHits {
                let closeFuzzy = try fuzzySearch(key: key, languages: languages, mode: mode, limit: 20, maxDistanceOverride: 1)
                if !closeFuzzy.isEmpty {
                    let fuzzyIds = Set(closeFuzzy.map(\.id))
                    let combined = Array((closeFuzzy + direct.filter { !fuzzyIds.contains($0.id) }).prefix(limit))
                    return SearchOutcome(
                        query: rawQuery,
                        results: combined,
                        searchedLanguages: languages,
                        suggestedMode: nil,
                        matchType: .fuzzy
                    )
                }
            }
            return SearchOutcome(query: rawQuery, results: direct, searchedLanguages: languages, suggestedMode: nil, matchType: .direct)
        }

        // Phase 1 fallback 2: bounded edit-distance typo tolerance
        if key.count >= 3 {
            let fuzzy = try fuzzySearch(key: key, languages: languages, mode: mode, limit: 20)
            if !fuzzy.isEmpty {
                return SearchOutcome(
                    query: rawQuery,
                    results: fuzzy,
                    searchedLanguages: languages,
                    suggestedMode: nil,
                    matchType: .fuzzy
                )
            }
        }

        // Fallback 3: a phrase that isn't an entry ("добрый день", "good morning") → look up each word.
        let wordResults = try wordByWordSearch(key: key, languages: languages, mode: mode, limit: limit)
        if !wordResults.isEmpty {
            return SearchOutcome(
                query: rawQuery,
                results: wordResults,
                searchedLanguages: languages,
                suggestedMode: nil,
                matchType: .words
            )
        }

        return SearchOutcome(query: rawQuery, results: [], searchedLanguages: languages, suggestedMode: nil)
    }

    /// Looks up each word of a multi-word key separately (exact form or base form first, then prefix),
    /// keeping query word order so a phrase reads left to right.
    private func wordByWordSearch(
        key: String,
        languages: Set<Language>,
        mode: DictionaryMode,
        limit: Int
    ) throws -> [SearchResult] {
        let words = key.split(separator: " ").map(String.init)
        guard words.count > 1 else { return [] }

        var seen: Set<Int64> = []
        var combined: [SearchResult] = []
        for word in words.prefix(8) where word.count >= 2 {
            var hits = try exactMatches(keys: [word], languages: languages, mode: mode, limit: 3)
            if hits.isEmpty {
                let stems = WordStemmer.candidateStems(for: word, languages: languages)
                if !stems.isEmpty {
                    hits = try exactMatches(keys: stems, languages: languages, mode: mode, limit: 2)
                }
            }
            if hits.isEmpty, word.count >= 3 {
                hits = try prefixSearch(key: word, languages: languages, mode: mode, limit: 2)
            }
            for hit in hits where seen.insert(hit.id).inserted {
                combined.append(hit)
            }
        }
        return Array(combined.prefix(limit))
    }

    private func exactMatches(
        keys: [String],
        languages: Set<Language>,
        mode: DictionaryMode,
        limit: Int
    ) throws -> [SearchResult] {
        let orderedLangs = languages.sorted { $0.rawValue < $1.rawValue }
        let langPlaceholders = orderedLangs.map { _ in "?" }.joined(separator: ",")
        let keyPlaceholders = keys.map { _ in "?" }.joined(separator: ",")
        let sql = """
        SELECT e.id, e.lang, e.headword, e.pos,
               \(Self.previewColumn(entry: "e", limit: 4)) AS preview
        FROM entries e
        WHERE e.lang IN (\(langPlaceholders))
          AND e.search_key IN (\(keyPlaceholders))
        ORDER BY e.frequency DESC, e.headword ASC
        LIMIT \(limit)
        """

        var bindings: [SQLiteValue] = [.text(mode.partner.rawValue)]
        orderedLangs.forEach { bindings.append(.text($0.rawValue)) }
        keys.forEach { bindings.append(.text($0)) }

        return try db.query(sql, bindings: bindings) { row in
            SearchResult(
                id: row.int64(0),
                language: Language(rawValue: row.string(1)) ?? .tajik,
                headword: row.string(2),
                pos: row.stringOrNil(3).flatMap(PartOfSpeech.init(rawValue:)),
                preview: row.stringOrNil(4) ?? ""
            )
        }
    }

    private func prefixSearch(
        key: String,
        languages: Set<Language>,
        mode: DictionaryMode,
        limit: Int
    ) throws -> [SearchResult] {
        let orderedLangs = languages.sorted { $0.rawValue < $1.rawValue }
        let placeholders = orderedLangs.map { _ in "?" }.joined(separator: ",")
        let sql = """
        SELECT e.id, e.lang, e.headword, e.pos,
               \(Self.previewColumn(entry: "e", limit: 4)) AS preview
        FROM entries e
        WHERE e.lang IN (\(placeholders))
          AND e.search_key >= ?
          AND e.search_key < ? || char(65535)
        ORDER BY (e.search_key = ?) DESC, e.frequency DESC, length(e.headword) ASC, e.headword ASC
        LIMIT \(limit)
        """

        var bindings: [SQLiteValue] = [.text(mode.partner.rawValue)]
        orderedLangs.forEach { bindings.append(.text($0.rawValue)) }
        bindings.append(.text(key))
        bindings.append(.text(key))
        bindings.append(.text(key))

        return try db.query(sql, bindings: bindings) { row in
            SearchResult(
                id: row.int64(0),
                language: Language(rawValue: row.string(1)) ?? .tajik,
                headword: row.string(2),
                pos: row.stringOrNil(3).flatMap(PartOfSpeech.init(rawValue:)),
                preview: row.stringOrNil(4) ?? ""
            )
        }
    }

    private func fuzzySearch(
        key: String,
        languages: Set<Language>,
        mode: DictionaryMode,
        limit: Int,
        maxDistanceOverride: Int? = nil
    ) throws -> [SearchResult] {
        let maxDist = maxDistanceOverride ?? (key.count >= 5 ? 2 : 1)
        let minLen = max(2, key.count - maxDist)
        let maxLen = key.count + maxDist
        let orderedLangs = languages.sorted { $0.rawValue < $1.rawValue }
        let placeholders = orderedLangs.map { _ in "?" }.joined(separator: ",")
        let sql = """
        SELECT e.id, e.lang, e.headword, e.pos, e.search_key, e.frequency,
               \(Self.previewColumn(entry: "e", limit: 4)) AS preview
        FROM entries e
        WHERE e.lang IN (\(placeholders))
          AND length(e.search_key) BETWEEN ? AND ?
        ORDER BY e.frequency DESC
        LIMIT 1500
        """

        var bindings: [SQLiteValue] = [.text(mode.partner.rawValue)]
        orderedLangs.forEach { bindings.append(.text($0.rawValue)) }
        bindings.append(.int64(Int64(minLen)))
        bindings.append(.int64(Int64(maxLen)))

        struct Scored {
            let dist: Int
            let freq: Int
            let result: SearchResult
        }

        let rows = try db.query(sql, bindings: bindings) { row -> Scored? in
            let candidateKey = row.string(4)
            let dist = WordStemmer.editDistance(key, candidateKey, maxDistance: maxDist)
            guard dist <= maxDist else { return nil }
            let result = SearchResult(
                id: row.int64(0),
                language: Language(rawValue: row.string(1)) ?? .tajik,
                headword: row.string(2),
                pos: row.stringOrNil(3).flatMap(PartOfSpeech.init(rawValue:)),
                preview: row.stringOrNil(6) ?? ""
            )
            return Scored(dist: dist, freq: row.int(5), result: result)
        }
        .compactMap { $0 }
        .sorted {
            if $0.dist != $1.dist { return $0.dist < $1.dist }
            return $0.freq > $1.freq
        }

        return Array(rows.prefix(limit).map(\.result))
    }

    func topics() throws -> [TopicCount] {
        try db.query(
            """
            SELECT topic, COUNT(*) AS cnt FROM entries
            WHERE lang = 'tg' AND topic IS NOT NULL AND topic != ''
            GROUP BY topic ORDER BY cnt DESC, topic ASC
            """
        ) { row in
            TopicCount(topic: row.string(0), count: row.int(1))
        }
    }

    func entries(inTopic topic: String, mode: DictionaryMode) throws -> [SearchResult] {
        try db.query(
            """
            SELECT e.id, e.lang, e.headword, e.pos,
                   \(Self.previewColumn(entry: "e", limit: 4, fixedPartner: true)) AS preview
            FROM entries e
            WHERE e.lang = 'tg' AND e.topic = ?
            ORDER BY e.frequency DESC, e.headword ASC
            """,
            bindings: [.text(mode.partner.rawValue), .text(topic)]
        ) { row in
            SearchResult(
                id: row.int64(0),
                language: Language(rawValue: row.string(1)) ?? .tajik,
                headword: row.string(2),
                pos: row.stringOrNil(3).flatMap(PartOfSpeech.init(rawValue:)),
                preview: row.stringOrNil(4) ?? ""
            )
        }
    }

    func entry(id: Int64) throws -> Entry? {
        let rows = try db.query(
            "SELECT id, lang, headword, pos, frequency, topic FROM entries WHERE id = ?",
            bindings: [.int64(id)]
        ) { row in
            Entry(
                id: row.int64(0),
                language: Language(rawValue: row.string(1)) ?? .tajik,
                headword: row.string(2),
                pos: row.stringOrNil(3).flatMap(PartOfSpeech.init(rawValue:)),
                frequency: row.int(4),
                topic: row.stringOrNil(5)
            )
        }
        return rows.first
    }

    func detail(id: Int64, mode: DictionaryMode = .tjRu) throws -> EntryDetail? {
        guard let entry = try entry(id: id) else { return nil }
        let translations = try db.query(
            """
            SELECT t2.id, t2.lang, t2.headword, t2.pos, t.note, t.position
            FROM translations t JOIN entries t2 ON t2.id = t.to_id
            WHERE t.from_id = ? ORDER BY t.position, t2.lang
            """,
            bindings: [.int64(id)]
        ) { row in
            Translation(
                entryId: row.int64(0),
                language: Language(rawValue: row.string(1)) ?? .tajik,
                headword: row.string(2),
                pos: row.stringOrNil(3).flatMap(PartOfSpeech.init(rawValue:)),
                note: row.stringOrNil(4),
                position: row.int(5)
            )
        }

        var index = 0
        var examples = try db.query(
            "SELECT tg, ru, en FROM examples WHERE entry_id = ?",
            bindings: [.int64(id)]
        ) { row in
            defer { index += 1 }
            return Example(id: index, tg: row.string(0), ru: row.stringOrNil(1), en: row.stringOrNil(2))
        }

        if examples.isEmpty, entry.language != .tajik,
           let primaryTgId = translations.first(where: { $0.language == .tajik })?.entryId {
            examples = try db.query(
                "SELECT tg, ru, en FROM examples WHERE entry_id = ? LIMIT 3",
                bindings: [.int64(primaryTgId)]
            ) { row in
                defer { index += 1 }
                return Example(id: index, tg: row.string(0), ru: row.stringOrNil(1), en: row.stringOrNil(2))
            }
        }

        let entryKey = TextNormalizer.searchKey(entry.headword)
        let previewPartner = entry.language == .tajik ? mode.partner.rawValue : Language.tajik.rawValue

        let homographs: [SearchResult] = entryKey.isEmpty ? [] : try db.query(
            """
            SELECT e2.id, e2.lang, e2.headword, e2.pos,
                   \(Self.previewColumn(entry: "e2", limit: 3, fixedPartner: true)) AS preview
            FROM entries e2
            WHERE e2.lang = ? AND e2.search_key = ? AND e2.id != ?
            ORDER BY e2.frequency DESC, e2.id ASC
            LIMIT 6
            """,
            bindings: [.text(previewPartner), .text(entry.language.rawValue), .text(entryKey), .int64(id)]
        ) { row in
            SearchResult(
                id: row.int64(0),
                language: Language(rawValue: row.string(1)) ?? .tajik,
                headword: row.string(2),
                pos: row.stringOrNil(3).flatMap(PartOfSpeech.init(rawValue:)),
                preview: row.stringOrNil(4) ?? ""
            )
        }

        let synonyms: [SearchResult] = try db.query(
            """
            SELECT e2.id, e2.lang, e2.headword, e2.pos,
                   \(Self.previewColumn(entry: "e2", limit: 2, fixedPartner: true)) AS preview,
                   COUNT(*) AS shared
            FROM translations t1
            JOIN translations t_rev ON t_rev.from_id = t1.to_id
            JOIN entries e2 ON e2.id = t_rev.to_id
            WHERE t1.from_id = ? AND e2.lang = ? AND e2.id != ? AND e2.search_key != ?
            GROUP BY e2.id
            ORDER BY shared DESC, e2.frequency DESC
            LIMIT 8
            """,
            bindings: [.text(previewPartner), .int64(id), .text(entry.language.rawValue), .int64(id), .text(entryKey)]
        ) { row in
            SearchResult(
                id: row.int64(0),
                language: Language(rawValue: row.string(1)) ?? .tajik,
                headword: row.string(2),
                pos: row.stringOrNil(3).flatMap(PartOfSpeech.init(rawValue:)),
                preview: row.stringOrNil(4) ?? ""
            )
        }

        let synonymIds = Set(synonyms.map(\.id))
        let homographIds = Set(homographs.map(\.id))
        let rootKey = entryKey.count >= 6 ? String(entryKey.dropLast()) : entryKey
        let relatedWords: [SearchResult]
        if rootKey.count >= 3 {
            let candidates = try db.query(
                """
                SELECT e2.id, e2.lang, e2.headword, e2.pos,
                       \(Self.previewColumn(entry: "e2", limit: 2, fixedPartner: true)) AS preview
                FROM entries e2
                WHERE e2.lang = ?
                  AND e2.search_key >= ?
                  AND e2.search_key < ? || char(65535)
                  AND e2.id != ?
                ORDER BY e2.frequency DESC, length(e2.headword) ASC
                LIMIT 12
                """,
                bindings: [.text(previewPartner), .text(entry.language.rawValue), .text(rootKey), .text(rootKey), .int64(id)]
            ) { row in
                SearchResult(
                    id: row.int64(0),
                    language: Language(rawValue: row.string(1)) ?? .tajik,
                    headword: row.string(2),
                    pos: row.stringOrNil(3).flatMap(PartOfSpeech.init(rawValue:)),
                    preview: row.stringOrNil(4) ?? ""
                )
            }
            relatedWords = Array(candidates.filter { !synonymIds.contains($0.id) && !homographIds.contains($0.id) }.prefix(8))
        } else {
            relatedWords = []
        }

        let grouped = Dictionary(grouping: translations, by: \.language)
        return EntryDetail(
            entry: entry,
            translations: grouped,
            examples: examples,
            homographs: homographs,
            synonyms: synonyms,
            relatedWords: relatedWords
        )
    }

    func wordOfTheDay(date: Date = .now) throws -> Entry? {
        let counts = try db.query("SELECT COUNT(*) FROM entries WHERE lang = 'tg' AND frequency >= 50") { $0.int(0) }
        guard let count = counts.first, count > 0 else { return nil }

        let calendar = Calendar(identifier: .gregorian)
        let startOfDay = calendar.startOfDay(for: date)
        let daysSinceEpoch = Int(floor(startOfDay.timeIntervalSince1970 / 86_400))
        let offset = ((daysSinceEpoch % count) + count) % count

        let rows = try db.query(
            "SELECT id, lang, headword, pos, frequency, topic FROM entries WHERE lang = 'tg' AND frequency >= 50 ORDER BY id LIMIT 1 OFFSET ?",
            bindings: [.int64(Int64(offset))]
        ) { row in
            Entry(
                id: row.int64(0),
                language: Language(rawValue: row.string(1)) ?? .tajik,
                headword: row.string(2),
                pos: row.stringOrNil(3).flatMap(PartOfSpeech.init(rawValue:)),
                frequency: row.int(4),
                topic: row.stringOrNil(5)
            )
        }
        return rows.first
    }

    func preview(id: Int64, mode: DictionaryMode) throws -> String {
        let rows = try db.query(
            "SELECT \(Self.previewColumn(entry: "e", limit: 4)) FROM entries e WHERE e.id = ?",
            bindings: [.text(mode.partner.rawValue), .int64(id)]
        ) { $0.stringOrNil(0) ?? "" }
        return rows.first ?? ""
    }

    func spotlightEntries(mode: DictionaryMode, limit: Int = 250) throws -> [SearchResult] {
        try db.query(
            """
            SELECT e.id, e.lang, e.headword, e.pos,
                   \(Self.previewColumn(entry: "e", limit: 4)) AS preview
            FROM entries e
            WHERE e.lang = 'tg'
            ORDER BY e.frequency DESC, e.id ASC
            LIMIT ?
            """,
            bindings: [.text(mode.partner.rawValue), .int64(Int64(limit))]
        ) { row in
            SearchResult(
                id: row.int64(0),
                language: Language(rawValue: row.string(1)) ?? .tajik,
                headword: row.string(2),
                pos: row.stringOrNil(3).flatMap(PartOfSpeech.init(rawValue:)),
                preview: row.stringOrNil(4) ?? ""
            )
        }
    }

    func info() throws -> DictionaryInfo {
        let pairs = try db.query("SELECT key, value FROM metadata") { ($0.string(0), $0.string(1)) }
        let dict = Dictionary(pairs, uniquingKeysWith: { _, latest in latest })
        return DictionaryInfo(dataVersion: dict["data_version"] ?? "", stats: dict["stats"] ?? "")
    }

    /// Resolves the current entry ID for `(lang, headword)` after a `dictionary.sqlite` update.
    func resolveEntryId(lang: String, headword: String) throws -> Int64? {
        let trimmed = headword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let direct = try queryIdByHeadwordOrKey(lang: lang, headword: trimmed) {
            return direct
        }

        if lang == Language.tajik.rawValue, Self.containsSovietTajikChars(trimmed) {
            let modernized = Self.modernizeSovietTajik(trimmed)
            if !modernized.isEmpty, modernized.caseInsensitiveCompare(trimmed) != .orderedSame {
                if let fallback = try queryIdByHeadwordOrKey(lang: lang, headword: modernized) {
                    return fallback
                }
            }
        }
        return nil
    }

    private func queryIdByHeadwordOrKey(lang: String, headword: String) throws -> Int64? {
        let exact = try db.query(
            "SELECT id FROM entries WHERE lang = ? AND LOWER(headword) = LOWER(?) ORDER BY frequency DESC, id ASC LIMIT 1",
            bindings: [.text(lang), .text(headword)]
        ) { $0.int64(0) }
        if let first = exact.first { return first }

        let key = TextNormalizer.searchKey(headword)
        guard !key.isEmpty else { return nil }
        let byKey = try db.query(
            "SELECT id FROM entries WHERE lang = ? AND search_key = ? ORDER BY frequency DESC, id ASC LIMIT 1",
            bindings: [.text(lang), .text(key)]
        ) { $0.int64(0) }
        return byKey.first
    }

    private static let sovietTajikChars = CharacterSet(charactersIn: "цщыьЦЩЫЬ")
    private static let tajikVowels = Set<Character>("аоуэиіїеёюяӯ")
    private static let explicitModernTajik: [String: String] = [
        "лыжа": "лижа",
        "лыжатозӣ": "лижатозӣ",
        "циркуль": "паргор",
        "цирк": "сирк",
        "цикл": "сикл",
        "цистерна": "систерна",
        "цитата": "иқтибос",
        "цемент": "семент",
        "цементӣ": "сементӣ",
        "цех": "сех",
        "центр": "марказ",
        "концерт": "консерт",
        "концертӣ": "консертӣ",
        "концерн": "консерн",
        "канцелярия": "канселярия",
        "канцеляриявӣ": "канселяриявӣ",
        "канцелярӣ": "канселярӣ",
        "рецензия": "тақриз",
        "офицер": "афсар",
        "принцип": "принсип",
        "медицина": "тиб",
        "медицинӣ": "тиббӣ",
        "дисциплина": "интизом",
        "лицей": "литсей",
        "социалист": "сотсиалист",
        "социалистӣ": "сотсиалистӣ",
        "социалӣ": "сотсиалӣ",
        "нацист": "натсист",
        "нацистӣ": "натсистӣ",
        "публицист": "публитсист",
        "публицистӣ": "публитсистӣ",
        "процент": "фоиз",
        "доцент": "дотсент",
        "акцент": "аксент",
        "абзац": "абзатс",
        "лоцман": "лотсман",
        "швейцариягӣ": "швейтсариягӣ",
        "швейцарӣ": "швейтсарӣ",
        "французӣ": "фаронсавӣ",
        "интернационал": "интернатсионал",
        "интернационалӣ": "интернатсионалӣ",
        "энциклопедия": "энсиклопедия",
        "энциклопедӣ": "энсиклопедӣ",
        "ассоциация": "ассотсиатсия",
        "концентрация": "консентратсия",
        "концентрационӣ": "консентратсионӣ",
        "концентрат": "консентрат",
        "милиционер": "милитсионер",
        "революционер": "револютсионер",
        "пьеса": "песа",
        "эскадрилья": "эскадриля",
        "батальон": "баталон",
        "интервью": "интервю",
        "судья": "судя",
        "фильм": "филм",
        "кинофильм": "кинофилм",
        "роль": "рол",
        "руль": "рул",
        "гриль": "грил",
        "пальто": "палто",
        "тюрьма": "маҳбас",
        "мадьюнӣ": "мадюнӣ",
    ]

    static func containsSovietTajikChars(_ text: String) -> Bool {
        text.rangeOfCharacter(from: sovietTajikChars) != nil
    }

    static func modernizeSovietTajik(_ raw: String) -> String {
        let w0 = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicit = explicitModernTajik[w0.lowercased()] {
            return explicit
        }
        var w = w0.replacingOccurrences(
            of: "([ғқҳҷзбдтсшрлнмвфкпг])ь([ие])",
            with: "$1й$2",
            options: [.regularExpression, .caseInsensitive]
        )
        w = w.replacingOccurrences(of: "ь", with: "").replacingOccurrences(of: "Ь", with: "")
        for v in tajikVowels {
            w = w.replacingOccurrences(of: "\(v)ция", with: "\(v)тсия", options: .caseInsensitive)
            w = w.replacingOccurrences(of: "\(v)цион", with: "\(v)тсион", options: .caseInsensitive)
        }
        w = w.replacingOccurrences(of: "ция", with: "сия", options: .caseInsensitive)
        w = w.replacingOccurrences(of: "цион", with: "сион", options: .caseInsensitive)
        w = w.replacingOccurrences(of: "ц", with: "тс").replacingOccurrences(of: "Ц", with: "Тс")
        w = w.replacingOccurrences(of: "щ", with: "ш").replacingOccurrences(of: "Щ", with: "Ш")
        w = w.replacingOccurrences(of: "ы", with: "и").replacingOccurrences(of: "Ы", with: "И")
        return w
    }

    /// Returns frequency-ordered Tajik candidates (plus optional cloze example) for the word-teaching game.
    func learningCandidates(
        topic: String? = nil,
        mode: DictionaryMode,
        maxFrequency: Int = 100,
        limit: Int = 450
    ) throws -> [WordCardCandidate] {
        let partnerCol = mode.partner == .russian ? "ex.ru" : "ex.en"
        let topicClause = topic == nil ? "" : "AND e.topic = ?"
        let freqClause = maxFrequency < 100 ? "AND e.frequency <= ?" : ""
        let sql = """
        SELECT e.id, e.lang, e.headword, e.pos, e.frequency, e.topic,
               \(Self.previewColumn(entry: "e", limit: 4, fixedPartner: true)) AS preview,
               (SELECT ex.tg FROM examples ex WHERE ex.entry_id = e.id LIMIT 1) AS ex_tg,
               (SELECT \(partnerCol) FROM examples ex WHERE ex.entry_id = e.id LIMIT 1) AS ex_partner
        FROM entries e
        WHERE e.lang = 'tg' AND e.frequency >= 40 \(topicClause) \(freqClause)
        ORDER BY e.frequency DESC, e.id ASC
        LIMIT ?
        """
        var bindings: [SQLiteValue] = [.text(mode.partner.rawValue)]
        if let topic {
            bindings.append(.text(topic))
        }
        if maxFrequency < 100 {
            bindings.append(.int64(Int64(maxFrequency)))
        }
        bindings.append(.int64(Int64(limit)))

        return try db.query(sql, bindings: bindings) { row in
            WordCardCandidate(
                entryId: row.int64(0),
                language: Language(rawValue: row.string(1)) ?? .tajik,
                headword: row.string(2),
                preview: row.stringOrNil(6) ?? "",
                pos: row.stringOrNil(3).flatMap(PartOfSpeech.init(rawValue:)),
                frequency: row.int(4),
                topic: row.stringOrNil(5),
                exampleTg: row.stringOrNil(7),
                examplePartner: row.stringOrNil(8)
            )
        }
    }

    func lexiconStats() throws -> LexiconStats {
        let rows = try db.query(
            """
            SELECT COUNT(*),
                   SUM(CASE WHEN frequency >= 90 THEN 1 ELSE 0 END),
                   SUM(CASE WHEN frequency BETWEEN 80 AND 89 THEN 1 ELSE 0 END),
                   SUM(CASE WHEN frequency BETWEEN 70 AND 79 THEN 1 ELSE 0 END),
                   SUM(CASE WHEN frequency < 70 THEN 1 ELSE 0 END)
            FROM entries
            WHERE lang = 'tg'
            """
        ) { row in
            LexiconStats(
                totalTajik: row.int(0),
                tier90Count: row.int(1),
                tier80Count: row.int(2),
                tier70Count: row.int(3),
                tierOtherCount: row.int(4)
            )
        }
        return rows.first ?? .fallback
    }

    /// Samples stratified Tajik entries across all 4 frequency tiers for the quick level placement test.
    func placementPool(mode: DictionaryMode) throws -> [WordCardCandidate] {
        let ranges: [(Int, Int)] = [(90, 100), (80, 89), (70, 79), (40, 69)]
        var combined: [WordCardCandidate] = []
        for (lo, hi) in ranges {
            let sql = """
            SELECT e.id, e.lang, e.headword, e.pos, e.frequency, e.topic,
                   \(Self.previewColumn(entry: "e", limit: 2, fixedPartner: true)) AS preview
            FROM entries e
            WHERE e.lang = 'tg' AND e.frequency BETWEEN ? AND ?
            ORDER BY RANDOM()
            LIMIT 25
            """
            let rows = try db.query(
                sql,
                bindings: [.text(mode.partner.rawValue), .int64(Int64(lo)), .int64(Int64(hi))]
            ) { row in
                WordCardCandidate(
                    entryId: row.int64(0),
                    language: Language(rawValue: row.string(1)) ?? .tajik,
                    headword: row.string(2),
                    preview: row.stringOrNil(6) ?? "",
                    pos: row.stringOrNil(3).flatMap(PartOfSpeech.init(rawValue:)),
                    frequency: row.int(4),
                    topic: row.stringOrNil(5),
                    exampleTg: nil,
                    examplePartner: nil
                )
            }
            combined.append(contentsOf: rows)
        }
        return combined
    }

    /// Fetches candidates for specific entry IDs (e.g. Favorites deck) in partner mode,
    /// normalizing any non-Tajik entry IDs to their primary Tajik entry.
    func learningCandidates(forEntryIds ids: [Int64], mode: DictionaryMode) throws -> [WordCardCandidate] {
        guard !ids.isEmpty else { return [] }
        let partnerCol = mode.partner == .russian ? "ex.ru" : "ex.en"
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let sql = """
        SELECT req.id, e.lang, e.headword, e.pos, e.frequency, e.topic,
               \(Self.previewColumn(entry: "e", limit: 4, fixedPartner: true)) AS preview,
               (SELECT ex.tg FROM examples ex WHERE ex.entry_id = e.id LIMIT 1) AS ex_tg,
               (SELECT \(partnerCol) FROM examples ex WHERE ex.entry_id = e.id LIMIT 1) AS ex_partner
        FROM entries req
        JOIN entries e ON e.id = CASE
            WHEN req.lang = 'tg' THEN req.id
            ELSE (
                SELECT t.to_id FROM translations t
                JOIN entries pe ON pe.id = t.to_id
                WHERE t.from_id = req.id AND pe.lang = 'tg'
                ORDER BY t.position ASC LIMIT 1
            )
        END
        WHERE req.id IN (\(placeholders))
        ORDER BY e.frequency DESC, req.id ASC
        """
        var bindings: [SQLiteValue] = [.text(mode.partner.rawValue)]
        ids.forEach { bindings.append(.int64($0)) }

        let rows = try db.query(sql, bindings: bindings) { row in
            WordCardCandidate(
                entryId: row.int64(0),
                language: Language(rawValue: row.string(1)) ?? .tajik,
                headword: row.string(2),
                preview: row.stringOrNil(6) ?? "",
                pos: row.stringOrNil(3).flatMap(PartOfSpeech.init(rawValue:)),
                frequency: row.int(4),
                topic: row.stringOrNil(5),
                exampleTg: row.stringOrNil(7),
                examplePartner: row.stringOrNil(8)
            )
        }
        return rows.filter { !$0.preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func topTajikHeadwords(limit: Int = 50) throws -> [String] {
        try db.query(
            "SELECT headword FROM entries WHERE lang = 'tg' ORDER BY frequency DESC, id ASC LIMIT ?",
            bindings: [.int64(Int64(limit))]
        ) { $0.string(0) }
    }
}
