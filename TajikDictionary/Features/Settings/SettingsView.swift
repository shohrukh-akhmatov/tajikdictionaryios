import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dictionaryRepository) private var repository
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Query(sort: \FavoriteItem.addedAt, order: .reverse) private var favorites: [FavoriteItem]
    @State private var info: DictionaryInfo?
    @State private var exportDocument: FavoritesBackupDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var backupMessage: String?
    @State private var showPlacementTest = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section(String(localized: "Dictionary mode")) {
                    ModeSwitcher(mode: $settings.mode)
                }

                Section(String(localized: "Appearance")) {
                    Picker(String(localized: "Theme"), selection: $settings.theme) {
                        ForEach(ThemeSetting.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker(String(localized: "Word size"), selection: $settings.fontScale) {
                        ForEach(FontScaleSetting.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(String(localized: "Pronunciation")) {
                    Toggle(String(localized: "Slow speech (0.75×)"), isOn: $settings.slowSpeech)
                }

                Section(String(localized: "Learning")) {
                    Picker(String(localized: "Daily word goal"), selection: $settings.dailyGoal) {
                        ForEach([5, 10, 15, 20], id: \.self) { goal in
                            Text("\(goal)").tag(goal)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        showPlacementTest = true
                    } label: {
                        LabeledContent(
                            String(localized: "Level Test"),
                            value: settings.placementLevel.map { "\($0.rawValue) · \($0.title)" } ?? String(localized: "Not taken")
                        )
                    }

                    NavigationLink {
                        StudyView()
                    } label: {
                        Label(String(localized: "Flashcards"), systemImage: "graduationcap")
                    }
                    NavigationLink {
                        GrammarGuideView()
                    } label: {
                        Label(String(localized: "Tajik Alphabet & Grammar"), systemImage: "text.book.closed")
                    }
                }

                Section(String(localized: "Backup & Transfer")) {
                    Button {
                        if let data = try? FavoritesBackup.encode(favorites) {
                            exportDocument = FavoritesBackupDocument(data: data)
                            isExporting = true
                        }
                    } label: {
                        Label(String(localized: "Export saved words (JSON)"), systemImage: "square.and.arrow.up")
                    }

                    Button {
                        isImporting = true
                    } label: {
                        Label(String(localized: "Import saved words (JSON)"), systemImage: "square.and.arrow.down")
                    }

                    if let backupMessage {
                        Text(backupMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(String(localized: "About")) {
                    LabeledContent(String(localized: "App"), value: "Tajik Dictionary 0.3.0")
                    LabeledContent(String(localized: "Dictionary version"), value: info?.dataVersion ?? "…")
                    if let stats = info?.stats, !stats.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Offline word counts"))
                            Text(stats)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "mailto:support@tajikdictionary.tj?subject=Tajik%20Dictionary%20Feedback")!) {
                        Label(String(localized: "Report a mistake / Suggest a word"), systemImage: "envelope")
                    }
                }
            }
            .navigationTitle(String(localized: "Settings"))
            .task {
                info = try? await repository.info()
            }
            .fullScreenCover(isPresented: $showPlacementTest) {
                PlacementTestView()
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "tajik-dictionary-favorites"
            ) { result in
                switch result {
                case .success:
                    backupMessage = String(localized: "Exported \(favorites.count) saved words")
                case .failure:
                    backupMessage = String(localized: "Could not save backup file")
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        let records = try FavoritesBackup.decodeRecords(from: data)
                        for record in records {
                            let targetId = record.entryId
                            let existing = (try? modelContext.fetch(
                                FetchDescriptor<FavoriteItem>(predicate: #Predicate { $0.entryId == targetId })
                            ))?.first
                            if let existing {
                                existing.lang = record.lang
                                existing.headword = record.headword
                                existing.preview = record.preview
                            } else {
                                modelContext.insert(FavoriteItem(
                                    entryId: record.entryId,
                                    lang: record.lang,
                                    headword: record.headword,
                                    preview: record.preview,
                                    addedAt: Date(timeIntervalSince1970: Double(record.addedAt) / 1000.0)
                                ))
                            }
                        }
                        try? modelContext.save()
                        backupMessage = String(localized: "Imported \(records.count) saved words")
                    } catch {
                        backupMessage = String(localized: "Could not read backup file")
                    }
                case .failure:
                    backupMessage = String(localized: "Could not read backup file")
                }
            }
        }
    }
}
