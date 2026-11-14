import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {
    private let repository: DictionaryRepository
    private var searchTask: Task<Void, Never>?

    var query: String = "" {
        didSet { scheduleSearch() }
    }

    var outcome: SearchOutcome = .empty
    var wordOfTheDay: (entry: Entry, preview: String)?

    init(repository: DictionaryRepository) {
        self.repository = repository
    }

    func refreshWordOfTheDay(mode: DictionaryMode) async {
        do {
            guard let entry = try await repository.wordOfTheDay() else {
                wordOfTheDay = nil
                return
            }
            let preview = try await repository.preview(id: entry.id, mode: mode)
            wordOfTheDay = (entry, preview)
        } catch {
            wordOfTheDay = nil
        }
    }

    func runSearchNow(mode: DictionaryMode) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            outcome = .empty
            return
        }
        do {
            outcome = try await repository.search(query: query, mode: mode)
        } catch {
            outcome = .empty
        }
    }

    func onModeChanged(_ mode: DictionaryMode) {
        scheduleSearch(currentMode: mode)
        Task { await refreshWordOfTheDay(mode: mode) }
    }

    private func scheduleSearch(currentMode: DictionaryMode? = nil) {
        searchTask?.cancel()
        let currentQuery = query
        if currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            outcome = .empty
            return
        }
        guard let mode = currentMode else { return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await runSearchNow(mode: mode)
        }
    }
}
