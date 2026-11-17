import AVFoundation
import SwiftUI

enum AppTheme {
    static let background = Color(
        light: Color(red: 0.980, green: 0.973, blue: 0.988), // #FAF8FC
        dark: Color(red: 0.071, green: 0.067, blue: 0.086)   // #121116
    )
    static let card = Color(
        light: .white,
        dark: Color(red: 0.110, green: 0.102, blue: 0.137)   // #1C1A23
    )
    static let cardSubtle = Color(
        light: Color(red: 0.957, green: 0.945, blue: 0.973), // #F4F1F8
        dark: Color(red: 0.141, green: 0.129, blue: 0.173)   // #24212C
    )
    static let textPrimary = Color(
        light: Color(red: 0.141, green: 0.129, blue: 0.165), // #24212A
        dark: Color(red: 0.949, green: 0.937, blue: 0.969)   // #F2EFF7
    )
    static let textSecondary = Color(
        light: Color(red: 0.384, green: 0.365, blue: 0.420), // #625D6B
        dark: Color(red: 0.718, green: 0.694, blue: 0.761)   // #B7B1C2
    )
    static let border = Color(
        light: Color(red: 0.875, green: 0.855, blue: 0.902), // #DFDAE6
        dark: Color(red: 0.212, green: 0.196, blue: 0.259)   // #363242
    )
    static let accent = Color(
        light: Color(red: 0.031, green: 0.463, blue: 0.325), // #087653
        dark: Color(red: 0.435, green: 0.847, blue: 0.675)   // #6FD8AC
    )
    static let accentSoft = Color(
        light: Color(red: 0.831, green: 0.953, blue: 0.898), // #D4F3E5
        dark: Color(red: 0.016, green: 0.322, blue: 0.224)   // #045239
    )
    static let onAccentSoft = Color(
        light: Color(red: 0.0, green: 0.129, blue: 0.086),   // #002116
        dark: Color(red: 0.780, green: 0.949, blue: 0.875)   // #C7F2DF
    )
}

private extension Color {
    init(light: Color, dark: Color) {
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

struct AppCard<Content: View>: View {
    var cornerRadius: CGFloat = 18
    var backgroundColor: Color = AppTheme.card
    var borderColor: Color = AppTheme.border.opacity(0.7)
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }
}

struct LanguageTag: View {
    let language: Language

    var body: some View {
        Text(language.tag)
            .font(.caption2.weight(.bold))
            .foregroundStyle(language.tagColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(language.tagColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel(language.displayName)
    }
}

struct PosBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(AppTheme.cardSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
    }
}

struct ModeSwitcher: View {
    @Binding var mode: DictionaryMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DictionaryMode.allCases) { item in
                let selected = mode == item
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        mode = item
                    }
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(selected ? .bold : .medium))
                        .foregroundStyle(selected ? .white : AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            selected ? AppTheme.accent : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AppTheme.cardSubtle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.border.opacity(0.6), lineWidth: 1)
        )
    }
}

struct TajikLettersBar: View {
    static let letters = ["ғ", "ӣ", "қ", "ӯ", "ҳ", "ҷ"]
    let onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.letters, id: \.self) { letter in
                    Button {
                        onTap(letter)
                    } label: {
                        Text(letter)
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppTheme.textPrimary)
                            .frame(width: 44, height: 36)
                            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(AppTheme.border.opacity(0.7), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct WordRowView: View {
    let language: Language
    let headword: String
    let pos: PartOfSpeech?
    let preview: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            LanguageTag(language: language)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 8) {
                    Text(headword)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    if let pos {
                        PosBadge(label: pos.label)
                    }
                }
                if !preview.isEmpty {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : currentX, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

@MainActor
@Observable
final class SpeechSpeaker {
    private let synthesizer = AVSpeechSynthesizer()

    func canSpeak(_ language: Language) -> Bool {
        switch language {
        case .russian, .english:
            return true
        case .tajik:
            return AVSpeechSynthesisVoice(language: "tg-TJ") != nil
        }
    }

    func speak(_ text: String, language: Language, rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        let localeId: String
        switch language {
        case .tajik:
            guard AVSpeechSynthesisVoice(language: "tg-TJ") != nil else { return }
            localeId = "tg-TJ"
        case .russian:
            localeId = "ru-RU"
        case .english:
            localeId = "en-US"
        }
        speak(text, localeIdentifier: localeId, rate: rate)
    }

    func speak(_ text: String, localeIdentifier: String, rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: localeIdentifier)
        utterance.rate = rate
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
