import SwiftUI

extension LearnerProfile {
    var localizedDisplayName: String {
        if id == Self.defaultProfileId && name == Self.defaultName {
            return String(localized: "Me")
        }
        return name
    }
}

extension Color {
    static func fromProfileHex(_ hex: String) -> Color {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard let rgb = UInt64(clean, radix: 16) else {
            return AppTheme.accent
        }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

struct ProfileAvatarCircle: View {
    let avatar: String
    let colorHex: String
    var size: CGFloat = 36
    var fontSize: CGFloat = 18

    var body: some View {
        let color = Color.fromProfileHex(colorHex)
        Text(avatar)
            .font(.system(size: fontSize))
            .frame(width: size, height: size)
            .background(color.opacity(0.18), in: Circle())
            .overlay(
                Circle().strokeBorder(color.opacity(0.55), lineWidth: 1.5)
            )
    }
}

/// Top-bar pill on the Learn screen showing the active learner and opening the switcher in 1 tap.
struct ProfileHeaderChip: View {
    let activeProfile: LearnerProfile
    let profileCount: Int
    let action: () -> Void

    var body: some View {
        let accent = Color.fromProfileHex(activeProfile.colorHex)
        Button(action: action) {
            HStack(spacing: 6) {
                ProfileAvatarCircle(
                    avatar: activeProfile.avatar,
                    colorHex: activeProfile.colorHex,
                    size: 26,
                    fontSize: 14
                )
                Text(activeProfile.localizedDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                if activeProfile.isChild {
                    Text(String(localized: "Kid mode"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accent.opacity(0.2), in: Capsule())
                } else if profileCount > 1 {
                    Text("\(profileCount)/\(LearnerProfile.maxProfiles)")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.leading, 5)
            .padding(.trailing, 10)
            .padding(.vertical, 4)
            .background(accent.opacity(0.12), in: Capsule())
            .overlay(
                Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Multi-user card on the Learn page:
/// - When 2..3 profiles exist: shows the Family & Learners board with streaks, XP, today's star, and 1-tap switching.
/// - When 1 profile exists: shows an invite card to add a family member (up to 3 local profiles).
struct FamilyLearnersCard: View {
    let profiles: [LearnerProfile]
    let activeProfile: LearnerProfile
    let activeSummary: GamificationSummary
    let statsByProfile: [String: ProfileStatsSnapshot]
    let onSelectProfile: (String) -> Void
    let onOpenSwitcher: () -> Void
    let onAddProfile: () -> Void

    private var todayKey: String {
        WordGameEngine.dateKey(for: .now)
    }

    private var rankedRows: [(profile: LearnerProfile, stat: ProfileStatsSnapshot)] {
        profiles.map { profile in
            let stat: ProfileStatsSnapshot
            if profile.id == activeProfile.id {
                stat = ProfileStatsSnapshot(
                    profileId: profile.id,
                    currentStreakDays: activeSummary.currentStreakDays,
                    longestStreakDays: activeSummary.longestStreakDays,
                    totalXp: activeSummary.totalXp,
                    masteredCount: activeSummary.masteredCount,
                    knownWordsCount: activeSummary.estimatedKnownWords,
                    todayReviewed: activeSummary.todayReviewed,
                    dailyGoal: activeSummary.dailyGoal,
                    cefrCode: activeSummary.cefrLevel.rawValue,
                    lastActiveDateKey: activeSummary.todayReviewed > 0 ? todayKey : statsByProfile[profile.id]?.lastActiveDateKey
                )
            } else {
                stat = statsByProfile[profile.id] ?? ProfileStatsSnapshot(
                    profileId: profile.id,
                    dailyGoal: profile.kind.defaultDailyGoal
                )
            }
            return (profile, stat)
        }
        .sorted { lhs, rhs in
            if lhs.stat.totalXp != rhs.stat.totalXp {
                return lhs.stat.totalXp > rhs.stat.totalXp
            }
            return lhs.stat.currentStreakDays > rhs.stat.currentStreakDays
        }
    }

    var body: some View {
        if profiles.count <= 1 {
            AppCard {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .font(.headline)
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 42, height: 42)
                        .background(AppTheme.accentSoft, in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(String(localized: "Learning with family?"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text("1/\(LearnerProfile.maxProfiles)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.cardSubtle, in: Capsule())
                        }
                        Text(String(localized: "Add up to \(LearnerProfile.maxProfiles) local profiles on this phone — each with their own streak, level & saved words."))
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Spacer(minLength: 0)

                    Button(action: onAddProfile) {
                        Label(String(localized: "Add learner"), systemImage: "person.badge.plus")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(14)
            }
        } else {
            AppCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(String(localized: "Family & Learners"))
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text(String(localized: "\(profiles.count) / \(LearnerProfile.maxProfiles) profiles"))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppTheme.accent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(AppTheme.accentSoft, in: Capsule())
                            }
                            Text(String(localized: "Tap any learner to switch in one tap"))
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        Spacer()
                        Button(String(localized: "Switch learner"), action: onOpenSwitcher)
                            .font(.caption.weight(.semibold))
                    }

                    ForEach(rankedRows, id: \.profile.id) { row in
                        let profile = row.profile
                        let stat = row.stat
                        let isCurrent = profile.id == activeProfile.id
                        let accent = Color.fromProfileHex(profile.colorHex)
                        let practicedToday = stat.practicedToday(todayDateKey: todayKey)

                        Button {
                            if !isCurrent {
                                onSelectProfile(profile.id)
                            } else {
                                onOpenSwitcher()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                ProfileAvatarCircle(
                                    avatar: profile.avatar,
                                    colorHex: profile.colorHex,
                                    size: 38,
                                    fontSize: 19
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(profile.localizedDisplayName)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                            .lineLimit(1)
                                        if isCurrent {
                                            Text(String(localized: "Active"))
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 2)
                                                .background(accent, in: Capsule())
                                        }
                                        if profile.isChild {
                                            Text(String(localized: "Kid mode"))
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(accent)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(accent.opacity(0.18), in: Capsule())
                                        }
                                    }
                                    Text("\(stat.totalXp) XP · \(stat.knownWordsCount) \(String(localized: "words"))")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                                Spacer(minLength: 0)
                                if practicedToday {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
                                        .accessibilityLabel(String(localized: "Practised today"))
                                }
                                HStack(spacing: 3) {
                                    Image(systemName: "flame.fill")
                                        .font(.caption)
                                        .foregroundStyle(stat.currentStreakDays > 0 ? .orange : AppTheme.textSecondary)
                                    Text("\(stat.currentStreakDays)d")
                                        .font(.caption.weight(.bold).monospacedDigit())
                                        .foregroundStyle(stat.currentStreakDays > 0 ? .orange : AppTheme.textSecondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                isCurrent ? accent.opacity(0.12) : AppTheme.cardSubtle,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(isCurrent ? accent.opacity(0.5) : .clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if profiles.count < LearnerProfile.maxProfiles {
                        Button(action: onAddProfile) {
                            Label(String(localized: "Add learner"), systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(16)
            }
        }
    }
}

/// Sheet listing all local learner profiles (up to 3), with 1-tap switching, add, and edit.
struct ProfileSwitcherSheet: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddEditor = false
    @State private var editingProfile: LearnerProfile?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(String(localized: "Tap a profile to switch streaks, progress and saved words."))
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        Text(String(localized: "\(settings.profiles.count) / \(LearnerProfile.maxProfiles) profiles"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(AppTheme.accentSoft, in: Capsule())
                    }

                    ForEach(settings.profiles) { profile in
                        let isSelected = profile.id == settings.activeProfile.id
                        let accent = Color.fromProfileHex(profile.colorHex)
                        let stat = settings.profileStats[profile.id]

                        HStack(spacing: 12) {
                            Button {
                                settings.switchProfile(to: profile.id)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    ProfileAvatarCircle(
                                        avatar: profile.avatar,
                                        colorHex: profile.colorHex,
                                        size: 46,
                                        fontSize: 22
                                    )
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(profile.localizedDisplayName)
                                                .font(.headline)
                                                .foregroundStyle(AppTheme.textPrimary)
                                            if profile.isChild {
                                                Text(String(localized: "Kid mode"))
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundStyle(accent)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(accent.opacity(0.2), in: Capsule())
                                            }
                                        }
                                        let subText: String = {
                                            if let stat {
                                                return "🔥 \(stat.currentStreakDays)d · \(stat.totalXp) XP · \(stat.cefrCode)"
                                            }
                                            return profile.isChild
                                                ? String(localized: "6-word rounds · choice & tiles only · no ads")
                                                : String(localized: "10-word rounds · typing & tiles")
                                        }()
                                        Text(subText)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                    Spacer(minLength: 0)
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(accent)
                                            .font(.title3)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                editingProfile = profile
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .frame(width: 34, height: 34)
                                    .background(AppTheme.cardSubtle, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "Edit profile"))
                        }
                        .padding(14)
                        .background(
                            isSelected ? accent.opacity(0.14) : AppTheme.cardSubtle,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(isSelected ? accent : .clear, lineWidth: 2)
                        )
                    }

                    if settings.profiles.count < LearnerProfile.maxProfiles {
                        Button {
                            showingAddEditor = true
                        } label: {
                            Label(String(localized: "Add learner"), systemImage: "person.badge.plus")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        Text(String(localized: "Limit of \(LearnerProfile.maxProfiles) profiles per phone reached."))
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.cardSubtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Divider()

                    HStack(spacing: 10) {
                        Image(systemName: "icloud.and.arrow.up")
                            .foregroundStyle(AppTheme.accent)
                        Text(String(localized: "Local profiles are automatically backed up with iCloud and can be exported anytime."))
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .padding(20)
            }
            .background(AppTheme.background)
            .navigationTitle(String(localized: "Who's learning?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done")) {
                        settings.recordProfileConfirmed()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAddEditor) {
                ProfileEditorSheet(initialProfile: nil)
            }
            .sheet(item: $editingProfile) { target in
                ProfileEditorSheet(initialProfile: target)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Sheet to create a new learner profile or edit/delete an existing profile.
struct ProfileEditorSheet: View {
    let initialProfile: LearnerProfile?

    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var avatar: String = LearnerProfile.defaultAvatar
    @State private var colorHex: String = LearnerProfile.defaultColor
    @State private var kind: ProfileKind = .adult
    @State private var confirmDelete = false

    private var canDelete: Bool {
        initialProfile != nil && settings.profiles.count > 1
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Learner name")) {
                    HStack(spacing: 12) {
                        ProfileAvatarCircle(avatar: avatar, colorHex: colorHex, size: 48, fontSize: 24)
                        TextField(String(localized: "e.g. Zarina"), text: $name)
                            .onChange(of: name) { _, newValue in
                                if newValue.count > 24 {
                                    name = String(newValue.prefix(24))
                                }
                            }
                    }
                }

                Section(String(localized: "Avatar")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                        ForEach(LearnerProfile.avatars, id: \.self) { item in
                            let selected = item == avatar
                            let accent = Color.fromProfileHex(colorHex)
                            Button {
                                avatar = item
                            } label: {
                                Text(item)
                                    .font(.title3)
                                    .frame(width: 42, height: 42)
                                    .background(selected ? accent.opacity(0.22) : AppTheme.cardSubtle, in: Circle())
                                    .overlay(
                                        Circle().strokeBorder(selected ? accent : .clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(String(localized: "Color")) {
                    HStack(spacing: 14) {
                        ForEach(LearnerProfile.colors, id: \.self) { hex in
                            let c = Color.fromProfileHex(hex)
                            let selected = hex.caseInsensitiveCompare(colorHex) == .orderedSame
                            Button {
                                colorHex = hex
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(c)
                                        .frame(width: 34, height: 34)
                                    if selected {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(String(localized: "Profile type")) {
                    Picker(String(localized: "Profile type"), selection: $kind) {
                        Text(String(localized: "Standard")).tag(ProfileKind.adult)
                        Text(String(localized: "Kid mode")).tag(ProfileKind.child)
                    }
                    .pickerStyle(.segmented)

                    Text(
                        kind == .child
                            ? String(localized: "6-word rounds · choice & tiles only · no ads")
                            : String(localized: "10-word rounds · typing & tiles")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if canDelete {
                    Section {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label(String(localized: "Delete profile"), systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(
                initialProfile == nil
                    ? String(localized: "Add learner")
                    : String(localized: "Edit profile")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Save")) {
                        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let resolvedName = finalName.isEmpty ? LearnerProfile.defaultName : finalName
                        if let existing = initialProfile {
                            settings.updateProfile(
                                id: existing.id,
                                name: resolvedName,
                                avatar: avatar,
                                colorHex: colorHex,
                                kind: kind
                            )
                        } else {
                            settings.addProfile(
                                name: resolvedName,
                                avatar: avatar,
                                colorHex: colorHex,
                                kind: kind,
                                switchToNew: true
                            )
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let p = initialProfile {
                    name = p.localizedDisplayName
                    avatar = p.avatar
                    colorHex = p.colorHex
                    kind = p.kind
                } else {
                    let count = settings.profiles.count
                    name = ""
                    avatar = LearnerProfile.avatars[count % LearnerProfile.avatars.count]
                    colorHex = LearnerProfile.colors[count % LearnerProfile.colors.count]
                    kind = .adult
                }
            }
            .alert(
                String(localized: "Delete \(initialProfile?.localizedDisplayName ?? "")?"),
                isPresented: $confirmDelete
            ) {
                Button(String(localized: "Remove"), role: .destructive) {
                    if let id = initialProfile?.id {
                        settings.deleteProfile(id: id)
                    }
                    dismiss()
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "This removes all learning progress and saved words for \(initialProfile?.localizedDisplayName ?? "") on this device."))
            }
        }
    }
}
