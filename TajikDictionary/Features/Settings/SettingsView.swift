import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dictionaryRepository) private var repository
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Query(sort: \FavoriteItem.addedAt, order: .reverse) private var favorites: [FavoriteItem]
    @Query private var flashcards: [FlashcardProgress]
    @Query private var dailyLogs: [DailyStudyLog]
    @State private var info: DictionaryInfo?
    @State private var exportDocument: FavoritesBackupDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var backupMessage: String?
    @State private var showPlacementTest = false
    @State private var showProfileSwitcher = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section(String(localized: "Dictionary mode")) {
                    ModeSwitcher(mode: $settings.mode)
                }

                Section(String(localized: "Learning language")) {
                    ModeSwitcher(mode: $settings.studyMode)
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
                    Button {
                        showProfileSwitcher = true
                    } label: {
                        HStack(spacing: 12) {
                            ProfileAvatarCircle(
                                avatar: settings.activeProfile.avatar,
                                colorHex: settings.activeProfile.colorHex,
                                size: 34,
                                fontSize: 17
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(settings.activeProfile.localizedDisplayName)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text(String(localized: "\(settings.profiles.count) / \(LearnerProfile.maxProfiles) profiles"))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if settings.profiles.count >= 2 {
                        Toggle(String(localized: "Ask “Who's learning?” on Learn tab"), isOn: $settings.askWhoIsLearning)
                    }

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
                    HStack(spacing: 12) {
                        Image(systemName: "icloud.and.arrow.up")
                            .foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "iCloud Auto Backup"))
                                .font(.subheadline.weight(.semibold))
                            Text(String(localized: "Up to \(LearnerProfile.maxProfiles) local profiles are backed up automatically & can be exported to iCloud Drive"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        if let data = try? settings.exportAllProfilesData() {
                            exportDocument = FavoritesBackupDocument(data: data)
                            isExporting = true
                        }
                    } label: {
                        Label(String(localized: "Export all profiles (iCloud Drive / JSON)"), systemImage: "square.and.arrow.up")
                    }

                    Button {
                        isImporting = true
                    } label: {
                        Label(String(localized: "Restore profiles from backup (JSON)"), systemImage: "square.and.arrow.down")
                    }

                    if let backupMessage {
                        Text(backupMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(String(localized: "About")) {
                    LabeledContent(String(localized: "App"), value: "\(String(localized: "Tajik Dictionary")) 0.3.0")
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
                    if AdsManager.shared.isPrivacyOptionsRequired {
                        Button {
                            Task { await AdsManager.shared.presentPrivacyOptions() }
                        } label: {
                            Label(String(localized: "Privacy settings"), systemImage: "hand.raised")
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Settings"))
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .task {
                info = try? await repository.info()
            }
            .fullScreenCover(isPresented: $showPlacementTest) {
                PlacementTestView()
            }
            .sheet(isPresented: $showProfileSwitcher) {
                ProfileSwitcherSheet()
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "tajik-dictionary-profiles"
            ) { result in
                switch result {
                case .success:
                    backupMessage = String(localized: "Exported \(favorites.count + flashcards.count) saved words")
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
                        let importedCount = try settings.importProfilesBackup(from: data)
                        backupMessage = String(localized: "Imported \(importedCount) saved words")
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
