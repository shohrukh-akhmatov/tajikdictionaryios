import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Portable JSON backup format shared across Android and iOS.
enum FavoritesBackup {
    static let currentVersion = 1

    struct Record: Codable, Equatable, Sendable {
        let entryId: Int64
        let lang: String
        let headword: String
        let preview: String
        let addedAt: Int64
    }

    struct Payload: Codable, Equatable, Sendable {
        let version: Int
        let exportedAt: Int64
        let favorites: [Record]
    }

    static func encode(_ items: [FavoriteItem], exportedAt: Date = .now) throws -> Data {
        let records = items.map { item in
            Record(
                entryId: item.entryId,
                lang: item.lang,
                headword: item.headword,
                preview: item.preview,
                addedAt: Int64(item.addedAt.timeIntervalSince1970 * 1000)
            )
        }
        return try encodeRecords(records, exportedAtMs: Int64(exportedAt.timeIntervalSince1970 * 1000))
    }

    static func encodeRecords(_ records: [Record], exportedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Payload(version: currentVersion, exportedAt: exportedAtMs, favorites: records))
    }

    static func decodeRecords(from data: Data) throws -> [Record] {
        let decoder = JSONDecoder()
        if let payload = try? decoder.decode(Payload.self, from: data) {
            return payload.favorites.filter { !$0.lang.isEmpty && !$0.headword.isEmpty }
        }
        let rawList = try decoder.decode([Record].self, from: data)
        return rawList.filter { !$0.lang.isEmpty && !$0.headword.isEmpty }
    }
}

struct FavoritesBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
