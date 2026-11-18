import SwiftUI

struct GrammarGuideView: View {
    private var letters: [(String, String, String)] {
        [
            ("Ғ ғ", "gh / г", String(localized: "voiced uvular fricative: ғамгин")),
            ("Ӣ ӣ", "ī / и", String(localized: "stressed long i at word ends: бинӣ, зиндагӣ")),
            ("Қ қ", "q / к", String(localized: "deep uvular k from back of throat: қалам, вақт")),
            ("Ӯ ӯ", "ū / у", String(localized: "rounded mid vowel: хӯрдан, кӯҳ, дӯст")),
            ("Ҳ ҳ", "h / х", String(localized: "soft breathy h: ҳафта, шаҳр")),
            ("Ҷ ҷ", "j / ч", String(localized: "English j in 'jam': ҷавоб, куҷо")),
        ]
    }

    private var patterns: [(String, String)] {
        [
            (
                String(localized: "Plural: -ҳо / -он"),
                String(localized: "китоб → китобҳо (books), дӯст → дӯстон (friends)")
            ),
            (
                String(localized: "Ezafe: -и"),
                String(localized: "хонаи калон (big house), китоби ман (my book)")
            ),
            (
                String(localized: "Object marker: -ро"),
                String(localized: "Дарро пӯшед. (Close the door.)")
            ),
            (
                String(localized: "Present tense: ме- + stem + ending"),
                String(localized: "рафтан → меравам (I go / am going)")
            ),
        ]
    }

    var body: some View {
        List {
            Section(String(localized: "Tajik-specific letters")) {
                ForEach(letters, id: \.0) { letter, fold, desc in
                    HStack(spacing: 14) {
                        Text(letter)
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 56, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fold).font(.headline)
                            Text(desc).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(String(localized: "Common grammar patterns")) {
                ForEach(patterns, id: \.0) { title, example in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline)
                        Text(example).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle(String(localized: "Tajik Alphabet & Grammar"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
