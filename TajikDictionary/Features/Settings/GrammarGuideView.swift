import SwiftUI

struct GrammarGuideView: View {
    private let letters: [(String, String, String)] = [
        ("Ғ ғ", "gh / г", "voiced uvular fricative: ғамгин"),
        ("Ӣ ӣ", "ī / и", "stressed long i at word ends: бинӣ, зиндагӣ"),
        ("Қ қ", "q / к", "deep uvular k from back of throat: қалам, вақт"),
        ("Ӯ ӯ", "ū / у", "rounded mid vowel: хӯрдан, кӯҳ, дӯст"),
        ("Ҳ ҳ", "h / х", "soft breathy h: ҳафта, шаҳр"),
        ("Ҷ ҷ", "j / ч", "English j in 'jam': ҷавоб, куҷо"),
    ]

    private let patterns: [(String, String)] = [
        ("Plural: -ҳо / -он", "китоб → китобҳо (books), дӯст → дӯстон (friends)"),
        ("Ezafe: -и", "хонаи калон (big house), китоби ман (my book)"),
        ("Object marker: -ро", "Дарро пӯшед. (Close the door.)"),
        ("Present tense: ме- + stem + ending", "рафтан → меравам (I go / am going)"),
    ]

    var body: some View {
        List {
            Section(String(localized: "Tajik-specific letters")) {
                ForEach(letters, id: \.0) { letter, fold, desc in
                    HStack(spacing: 14) {
                        Text(letter)
                            .font(.title2.bold())
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
        .navigationTitle(String(localized: "Tajik Alphabet & Grammar"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
