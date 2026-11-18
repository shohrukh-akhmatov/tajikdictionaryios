import Foundation
import SQLite3
import SwiftUI
import WidgetKit

struct WordOfTheDayWidgetEntry: TimelineEntry {
    let date: Date
    let entryId: Int64
    let headword: String
    let previewRu: String
    let previewEn: String
}

private enum WidgetDictionaryLoader {
    static func wordOfTheDay(for date: Date = .now) -> WordOfTheDayWidgetEntry {
        let fallback = WordOfTheDayWidgetEntry(
            date: date,
            entryId: 1,
            headword: "салом",
            previewRu: "привет",
            previewEn: "hello"
        )
        guard let url = Bundle.main.url(forResource: "dictionary", withExtension: "sqlite") else {
            return fallback
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return fallback
        }
        defer { sqlite3_close(db) }

        var countStmt: OpaquePointer?
        var count = 0
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM entries WHERE lang = 'tg' AND frequency >= 50", -1, &countStmt, nil) == SQLITE_OK {
            if sqlite3_step(countStmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int64(countStmt, 0))
            }
        }
        sqlite3_finalize(countStmt)
        guard count > 0 else { return fallback }

        let calendar = Calendar(identifier: .gregorian)
        let startOfDay = calendar.startOfDay(for: date)
        let daysSinceEpoch = Int(floor(startOfDay.timeIntervalSince1970 / 86_400))
        let offset = ((daysSinceEpoch % count) + count) % count

        var entryId: Int64 = 1
        var headword = "салом"
        var entryStmt: OpaquePointer?
        if sqlite3_prepare_v2(
            db,
            "SELECT id, headword FROM entries WHERE lang = 'tg' AND frequency >= 50 ORDER BY id LIMIT 1 OFFSET ?",
            -1,
            &entryStmt,
            nil
        ) == SQLITE_OK {
            sqlite3_bind_int64(entryStmt, 1, Int64(offset))
            if sqlite3_step(entryStmt) == SQLITE_ROW {
                entryId = sqlite3_column_int64(entryStmt, 0)
                if let cStr = sqlite3_column_text(entryStmt, 1) {
                    headword = String(cString: cStr)
                }
            }
        }
        sqlite3_finalize(entryStmt)

        let ru = preview(db: db, entryId: entryId, partnerLang: "ru")
        let en = preview(db: db, entryId: entryId, partnerLang: "en")
        return WordOfTheDayWidgetEntry(date: date, entryId: entryId, headword: headword, previewRu: ru, previewEn: en)
    }

    private static func preview(db: OpaquePointer, entryId: Int64, partnerLang: String) -> String {
        let sql = """
        SELECT group_concat(h, ', ') FROM (
            SELECT t2.headword AS h FROM translations t
            JOIN entries t2 ON t2.id = t.to_id
            WHERE t.from_id = ? AND t2.lang = ?
            ORDER BY t.position LIMIT 3)
        """
        var stmt: OpaquePointer?
        var out = ""
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, entryId)
            sqlite3_bind_text(stmt, 2, partnerLang, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if sqlite3_step(stmt) == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) {
                out = String(cString: cStr)
            }
        }
        sqlite3_finalize(stmt)
        return out
    }
}

struct WordOfTheDayProvider: TimelineProvider {
    func placeholder(in context: Context) -> WordOfTheDayWidgetEntry {
        WordOfTheDayWidgetEntry(date: .now, entryId: 1, headword: "салом", previewRu: "привет", previewEn: "hello")
    }

    func getSnapshot(in context: Context, completion: @escaping (WordOfTheDayWidgetEntry) -> Void) {
        completion(WidgetDictionaryLoader.wordOfTheDay())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WordOfTheDayWidgetEntry>) -> Void) {
        let now = Date()
        let entry = WidgetDictionaryLoader.wordOfTheDay(for: now)
        let nextDay = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        completion(Timeline(entries: [entry], policy: .after(nextDay)))
    }
}

struct WordOfTheDayWidgetView: View {
    var entry: WordOfTheDayWidgetEntry

    private var widgetHeaderLabel: String {
        let code = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
        switch code {
        case "ru": return "СЛОВО ДНЯ"
        case "tg": return "КАЛИМАИ РӮЗ"
        default: return "WORD OF THE DAY"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(widgetHeaderLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.teal)
                Spacer()
                Text("TJ")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.teal.opacity(0.15), in: Capsule())
                    .foregroundStyle(.teal)
            }

            Text(entry.headword)
                .font(.title3.weight(.bold))
                .lineLimit(1)

            if !entry.previewRu.isEmpty {
                Text(entry.previewRu)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !entry.previewEn.isEmpty {
                Text(entry.previewEn)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "tajikdictionary://entry/\(entry.entryId)"))
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct TajikWordOfTheDayWidget: Widget {
    let kind = "TajikWordOfTheDayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WordOfTheDayProvider()) { entry in
            WordOfTheDayWidgetView(entry: entry)
        }
        .configurationDisplayName("Word of the Day")
        .description("Learn a new Tajik word offline every day.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
