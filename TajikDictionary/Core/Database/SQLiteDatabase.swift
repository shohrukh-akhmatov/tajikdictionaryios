import Foundation
import SQLite3

enum SQLiteError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "SQLite open failed: \(msg)"
        case .prepareFailed(let msg): return "SQLite prepare failed: \(msg)"
        case .stepFailed(let msg): return "SQLite step failed: \(msg)"
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thin read-only SQLite3 wrapper. Used inside `DictionaryRepository` actor.
final class SQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?

    init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let db { sqlite3_close(db) }
            throw SQLiteError.openFailed(msg)
        }
        self.handle = db
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    func query<T>(_ sql: String, bindings: [SQLiteValue] = [], map: (SQLiteRow) -> T) throws -> [T] {
        guard let handle else { return [] }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) != SQLITE_OK {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(stmt) }

        for (index, value) in bindings.enumerated() {
            let col = Int32(index + 1)
            switch value {
            case .text(let s):
                sqlite3_bind_text(stmt, col, s, -1, sqliteTransient)
            case .int64(let n):
                sqlite3_bind_int64(stmt, col, n)
            }
        }

        var rows: [T] = []
        let row = SQLiteRow(stmt: stmt)
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                rows.append(map(row))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw SQLiteError.stepFailed(String(cString: sqlite3_errmsg(handle)))
            }
        }
        return rows
    }
}

enum SQLiteValue {
    case text(String)
    case int64(Int64)
}

struct SQLiteRow {
    fileprivate let stmt: OpaquePointer?

    func int64(_ index: Int32) -> Int64 {
        sqlite3_column_int64(stmt, index)
    }

    func int(_ index: Int32) -> Int {
        Int(sqlite3_column_int64(stmt, index))
    }

    func string(_ index: Int32) -> String {
        stringOrNil(index) ?? ""
    }

    func stringOrNil(_ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let cStr = sqlite3_column_text(stmt, index) else {
            return nil
        }
        return String(cString: cStr)
    }
}
