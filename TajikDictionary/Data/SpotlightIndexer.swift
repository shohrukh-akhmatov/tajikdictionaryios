import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Indexes top dictionary entries and saved favorites into iOS CoreSpotlight for system-wide lookup.
enum SpotlightIndexer {
    private static let domainIdentifier = "tj.tajikdictionary.entries"
    private static let identifierPrefix = "tj.tajikdictionary.entry."

    static func indexEntries(_ items: [SearchResult]) async {
        let searchableItems = items.map { item -> CSSearchableItem in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = item.headword
            attrs.contentDescription = item.preview.isEmpty
                ? item.language.tag
                : "\(item.language.tag) · \(item.preview)"
            attrs.keywords = [item.headword, item.preview]
            return CSSearchableItem(
                uniqueIdentifier: "\(identifierPrefix)\(item.id)",
                domainIdentifier: domainIdentifier,
                attributeSet: attrs
            )
        }
        guard !searchableItems.isEmpty else { return }
        try? await CSSearchableIndex.default().indexSearchableItems(searchableItems)
    }

    static func entryId(from userActivity: NSUserActivity) -> Int64? {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              identifier.hasPrefix(identifierPrefix) else {
            return nil
        }
        return Int64(identifier.dropFirst(identifierPrefix.count))
    }

    static func entryId(from url: URL) -> Int64? {
        guard url.scheme == "tajikdictionary", url.host == "entry",
              let last = url.pathComponents.last else {
            return nil
        }
        return Int64(last)
    }
}
