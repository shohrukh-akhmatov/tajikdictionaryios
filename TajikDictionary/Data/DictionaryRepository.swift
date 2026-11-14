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
        if !direct.isEmpty {
            return SearchOutcome(query: rawQuery, results: direct, searchedLanguages: languages, suggestedMode: nil, matchType: .direct)
        }

        // Phase 1 fallback 1: morphological stem hints
        let stems = WordStemmer.candidateStems(for: key, languages: languages)
        if !stems.isEmpty {
            var seen = Set<Int64>()
            var stemResults: [SearchResult] = []
            for stem in stems {
                for item in try prefixSearch(key: stem, languages: languages, mode: mode, limit: 15) {
                    if seen.insert(item.id).inserted {
                        stemResults.append(item)
                    }
                }
                if stemResults.count >= limit { break }
            }
            if !stemResults.isEmpty {
                return SearchOutcome(
                    query: rawQuery,
                    results: Array(stemResults.prefix(limit)),
                    searchedLanguages: languages,
                    suggestedMode: nil,
                    matchType: .stem
                )
            }
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

        return SearchOutcome(query: rawQuery, results: [], searchedLanguages: languages, suggestedMode: nil)
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
               (SELECT group_concat(h, ', ') FROM (
                    SELECT t2.headword AS h
                    FROM translations t JOIN entries t2 ON t2.id = t.to_id
                    WHERE t.from_id = e.id
                      AND t2.lang = CASE WHEN e.lang = 'tg' THEN ? ELSE 'tg' END
                    ORDER BY t.position LIMIT 4)) AS preview
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
        limit: Int
    ) throws -> [SearchResult] {
        let maxDist = key.count >= 5 ? 2 : 1
        let minLen = max(2, key.count - maxDist)
        let maxLen = key.count + maxDist
        let orderedLangs = languages.sorted { $0.rawValue < $1.rawValue }
        let placeholders = orderedLangs.map { _ in "?" }.joined(separator: ",")
        let sql = """
        SELECT e.id, e.lang, e.headword, e.pos, e.search_key, e.frequency,
               (SELECT group_concat(h, ', ') FROM (
                    SELECT t2.headword AS h
                    FROM translations t JOIN entries t2 ON t2.id = t.to_id
                    WHERE t.from_id = e.id
                      AND t2.lang = CASE WHEN e.lang = 'tg' THEN ? ELSE 'tg' END
                    ORDER BY t.position LIMIT 4)) AS preview
        FROM entries e
        WHERE e.lang IN (\(placeholders))
          AND length(e.search_key) BETWEEN ? AND ?
        ORDER BY e.frequency DESC
        LIMIT 400
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
                   (SELECT group_concat(h, ', ') FROM (
                        SELECT t2.headword AS h
                        FROM translations t JOIN entries t2 ON t2.id = t.to_id
                        WHERE t.from_id = e.id AND t2.lang = ?
                        ORDER BY t.position LIMIT 4)) AS preview
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

    func detail(id: Int64) throws -> EntryDetail? {
        guard let entry = try entry(id: id) else { return nil }
        let translations = try db.query(
            """
            SELECT t2.id, t2.lang, t2.headword, t2.pos, t.note
            FROM translations t JOIN entries t2 ON t2.id = t.to_id
            WHERE t.from_id = ? ORDER BY t2.lang, t.position
            """,
            bindings: [.int64(id)]
        ) { row in
            Translation(
                entryId: row.int64(0),
                language: Language(rawValue: row.string(1)) ?? .tajik,
                headword: row.string(2),
                pos: row.stringOrNil(3).flatMap(PartOfSpeech.init(rawValue:)),
                note: row.stringOrNil(4)
            )
        }

        var index = 0
        let examples = try db.query(
            "SELECT tg, ru, en FROM examples WHERE entry_id = ?",
            bindings: [.int64(id)]
        ) { row in
            defer { index += 1 }
            return Example(id: index, tg: row.string(0), ru: row.stringOrNil(1), en: row.stringOrNil(2))
        }

        let grouped = Dictionary(grouping: translations, by: \.language)
        return EntryDetail(entry: entry, translations: grouped, examples: examples)
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
            """
            SELECT group_concat(h, ', ') FROM (
                SELECT t2.headword AS h FROM translations t
                JOIN entries e ON e.id = t.from_id
                JOIN entries t2 ON t2.id = t.to_id
                WHERE t.from_id = ? AND t2.lang = CASE WHEN e.lang = 'tg' THEN ? ELSE 'tg' END
                ORDER BY t.position LIMIT 4)
            """,
            bindings: [.int64(id), .text(mode.partner.rawValue)]
        ) { $0.stringOrNil(0) ?? "" }
        return rows.first ?? ""
    }

    func info() throws -> DictionaryInfo {
        let pairs = try db.query("SELECT key, value FROM metadata") { ($0.string(0), $0.string(1)) }
        let dict = Dictionary(pairs, uniquingKeysWith: { _, latest in latest })
        return DictionaryInfo(dataVersion: dict["data_version"] ?? "", stats: dict["stats"] ?? "")
    }
}
