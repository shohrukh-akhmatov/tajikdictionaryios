import SwiftUI

struct LanguageTag: View {
    let language: Language

    var body: some View {
        Text(language.tag)
            .font(.caption2.weight(.bold))
            .foregroundStyle(language.tagColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(language.tagColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel(language.displayName)
    }
}

struct ModeSwitcher: View {
    @Binding var mode: DictionaryMode

    var body: some View {
        Picker(String(localized: "Dictionary mode"), selection: $mode) {
            ForEach(DictionaryMode.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
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
                            .frame(minWidth: 36, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 2)
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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(headword)
                        .font(.body.weight(.semibold))
                    if let pos {
                        Text(pos.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !preview.isEmpty {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
