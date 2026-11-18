import SwiftUI

/// First-launch flow: welcome → language → daily goal → level. Every step can be skipped and everything
/// chosen here can be changed later in Settings or on the Learn screen.
struct OnboardingView: View {
    /// Called once at the end. `startPlacement` is true when the user chose to check their level now.
    let onFinish: (_ startPlacement: Bool) -> Void

    @Environment(SettingsStore.self) private var settings
    @State private var step = 0

    private let stepCount = 4

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if step > 0 {
                    Button {
                        withAnimation { step -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                    }
                    .accessibilityLabel(String(localized: "Back"))
                }
                Spacer()
                if step > 0 {
                    Button(String(localized: "Skip")) { onFinish(false) }
                        .font(.subheadline.weight(.semibold))
                }
            }
            .tint(AppTheme.accent)
            .frame(height: 44)
            .padding(.horizontal, 20)

            Group {
                switch step {
                case 0: welcomeStep
                case 1: languageStep
                case 2: goalStep
                default: levelStep
                }
            }
            .frame(maxWidth: 520, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .opacity))
            .id(step)

            pageDots
                .padding(.bottom, 16)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    // MARK: Steps

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "character.book.closed.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 120, height: 120)
                .background(AppTheme.accentSoft, in: Circle())
            VStack(spacing: 8) {
                Text(String(localized: "Welcome to Tajik Dictionary"))
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(verbatim: "Луғати тоҷикӣ")
                    .font(.headline)
                    .foregroundStyle(AppTheme.accent)
            }
            VStack(alignment: .leading, spacing: 14) {
                featureRow(icon: "magnifyingglass", text: String(localized: "Search 16,000+ words, even offline"))
                featureRow(icon: "gamecontroller.fill", text: String(localized: "Learn words with a short daily game"))
                featureRow(icon: "star.fill", text: String(localized: "Save words and track your progress"))
            }
            .padding(.top, 8)
            Spacer()
            primaryButton(String(localized: "Get started")) { next() }
        }
    }

    private var languageStep: some View {
        VStack(spacing: 20) {
            stepHeader(
                title: String(localized: "Which language do you know?"),
                subtitle: String(localized: "Translations and the learning game will use it. You can change it anytime.")
            )
            VStack(spacing: 12) {
                languageOption(.tjRu, native: "Русский")
                languageOption(.tjEn, native: "English")
            }
            Spacer()
        }
    }

    private var goalStep: some View {
        VStack(spacing: 20) {
            stepHeader(
                title: String(localized: "Set a daily goal"),
                subtitle: String(localized: "A few words every day works better than many once a week.")
            )
            VStack(spacing: 10) {
                goalOption(5, label: String(localized: "Casual"))
                goalOption(10, label: String(localized: "Regular"))
                goalOption(15, label: String(localized: "Serious"))
                goalOption(20, label: String(localized: "Intense"))
            }
            Spacer()
        }
    }

    private var levelStep: some View {
        VStack(spacing: 20) {
            stepHeader(
                title: String(localized: "Do you already know some Tajik?"),
                subtitle: String(localized: "A 1-minute test lets the game skip words you already know.")
            )
            VStack(spacing: 12) {
                choiceCard(
                    icon: "slider.horizontal.3",
                    title: String(localized: "Check my level"),
                    subtitle: String(localized: "1-minute test"),
                    selected: false
                ) { finish(startPlacement: true) }
                choiceCard(
                    icon: "leaf.fill",
                    title: String(localized: "I'm a beginner"),
                    subtitle: String(localized: "Start with the most common words"),
                    selected: false
                ) { finish(startPlacement: false) }
            }
            Spacer()
        }
    }

    // MARK: Building blocks

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 32)
            Text(text)
                .font(.body)
                .foregroundStyle(AppTheme.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private func languageOption(_ mode: DictionaryMode, native: String) -> some View {
        choiceCard(
            icon: "globe",
            title: native,
            subtitle: "\(Language.tajik.displayName) ⇄ \(mode.partner.displayName)",
            selected: settings.mode == mode
        ) {
            settings.mode = mode
            settings.studyMode = mode
            next()
        }
    }

    private func goalOption(_ goal: Int, label: String) -> some View {
        choiceCard(
            icon: "target",
            title: label,
            subtitle: String(localized: "\(goal) words a day"),
            selected: settings.dailyGoal == goal
        ) {
            settings.dailyGoal = goal
            next()
        }
    }

    private func choiceCard(icon: String, title: String, subtitle: String, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.accentSoft, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(selected ? AppTheme.accent : AppTheme.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(AppTheme.cardSubtle, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? AppTheme.accent : .clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(AppTheme.accent)
        .padding(.bottom, 8)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<stepCount, id: \.self) { index in
                Capsule()
                    .fill(index == step ? AppTheme.accent : AppTheme.cardSubtle)
                    .frame(width: index == step ? 20 : 8, height: 8)
            }
        }
        .animation(.easeInOut, value: step)
        .accessibilityHidden(true)
    }

    private func next() {
        withAnimation { step = min(step + 1, stepCount - 1) }
    }

    private func finish(startPlacement: Bool) {
        onFinish(startPlacement)
    }
}
