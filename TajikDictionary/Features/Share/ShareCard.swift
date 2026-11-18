import CoreImage.CIFilterBuiltins
import SwiftUI
import UniformTypeIdentifiers

/// Public links used on share cards and in share text.
/// The download page will live on GitHub Pages — replace `shareURL` once it is published (single source of truth).
enum AppLinks {
    static let shareURL = URL(string: "https://shohrukh-akhmatov.github.io/tajikdictionary/")!
    static let hashtag = "#LearnTajik"

    /// Host + path without scheme, for printing on the card ("shohrukh-akhmatov.github.io/tajikdictionary").
    static var displayURL: String {
        var text = shareURL.absoluteString
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }
}

struct ShareCardStat: Hashable, Sendable {
    let value: String
    let label: String
}

/// Everything a share card shows. Built from round results, placement results, streaks and badges.
struct ShareCardContent: Hashable, Sendable {
    var symbol: String
    var headline: String
    var subtitle: String?
    var stats: [ShareCardStat]
    var date: Date = Calendar.current.startOfDay(for: .now)

    /// Text that accompanies the image (many apps drop the image or the text, so both carry the link).
    var shareText: String {
        var lines = [headline]
        if let subtitle { lines.append(subtitle) }
        lines.append(stats.map { "\($0.label): \($0.value)" }.joined(separator: " · "))
        lines.append("\(String(localized: "Learn Tajik for free, even offline")) \(AppLinks.hashtag)")
        lines.append(AppLinks.shareURL.absoluteString)
        return lines.joined(separator: "\n")
    }
}

extension ShareCardContent {
    static func round(xp: Int, accuracy: Int, newWords: Int, streakDays: Int, cefr: String) -> ShareCardContent {
        var stats = [
            ShareCardStat(value: "+\(xp)", label: "XP"),
            ShareCardStat(value: "\(accuracy)%", label: String(localized: "Accuracy")),
        ]
        if newWords > 0 { stats.append(ShareCardStat(value: "\(newWords)", label: String(localized: "New words"))) }
        if streakDays > 0 { stats.append(ShareCardStat(value: "\(streakDays)", label: String(localized: "Streak"))) }
        return ShareCardContent(
            symbol: "trophy.fill",
            headline: String(localized: "Round complete!"),
            subtitle: String(localized: "My Tajik level: \(cefr)"),
            stats: stats
        )
    }

    static func placement(_ result: PlacementResult) -> ShareCardContent {
        ShareCardContent(
            symbol: "graduationcap.fill",
            headline: String(localized: "My Tajik level: \(result.cefrLevel.rawValue)"),
            subtitle: result.cefrLevel.title,
            stats: [
                ShareCardStat(value: "~\(result.estimatedKnownWords)", label: String(localized: "Known words")),
                ShareCardStat(value: String(format: "%.0f%%", result.textRecognitionPercent), label: String(localized: "Text recognized")),
                ShareCardStat(value: "\(result.correctCount)/\(result.totalCount)", label: String(localized: "Score")),
            ]
        )
    }

    static func progress(_ summary: GamificationSummary) -> ShareCardContent {
        let headline = summary.currentStreakDays > 0
            ? String(localized: "\(summary.currentStreakDays)-day streak!")
            : String(localized: "My Tajik progress")
        return ShareCardContent(
            symbol: "flame.fill",
            headline: headline,
            subtitle: String(localized: "Level \(summary.level) · \(summary.levelTitle)"),
            stats: [
                ShareCardStat(value: "\(summary.totalXp)", label: "XP"),
                ShareCardStat(value: "\(summary.masteredCount)", label: String(localized: "Mastered")),
                ShareCardStat(value: "~\(summary.estimatedKnownWords)", label: String(localized: "Known words")),
                ShareCardStat(value: summary.cefrLevel.rawValue, label: String(localized: "Level")),
            ]
        )
    }

    static func badge(_ badge: AchievementBadge, summary: GamificationSummary) -> ShareCardContent {
        ShareCardContent(
            symbol: badge.systemImage,
            headline: String(localized: "Achievement unlocked"),
            subtitle: "\(badge.title) — \(badge.subtitle)",
            stats: [
                ShareCardStat(value: "\(summary.totalXp)", label: "XP"),
                ShareCardStat(value: "\(summary.longestStreakDays)", label: String(localized: "Best streak")),
            ]
        )
    }
}

// MARK: - Card view (rendered off-screen, fixed light palette so it looks the same everywhere)

struct ShareCardView: View {
    static let size = CGSize(width: 360, height: 450)   // × 3 = 1080 × 1350 (4:5, fits Instagram/Telegram/WhatsApp)

    let content: ShareCardContent
    var qrCode: UIImage?

    private let deep = Color(red: 0.016, green: 0.224, blue: 0.157)    // #04392A
    private let accent = Color(red: 0.031, green: 0.463, blue: 0.325)  // #087653 (AppTheme.accent, light)
    private let mint = Color(red: 0.435, green: 0.847, blue: 0.675)    // #6FD8AC

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "character.book.closed.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(deep)
                    .frame(width: 30, height: 30)
                    .background(mint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Tajik Dictionary")
                        .font(.system(size: 14, weight: .bold))
                    Text(verbatim: "Луғати тоҷикӣ")
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0.75)
                }
                Spacer()
                Text(content.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.75)
            }

            Spacer(minLength: 18)

            Image(systemName: content.symbol)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.yellow)
                .padding(.bottom, 10)

            Text(content.headline)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if let subtitle = content.subtitle {
                Text(subtitle)
                    .font(.system(size: 15, weight: .semibold))
                    .opacity(0.85)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 4)
            }

            Spacer(minLength: 16)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(content.stats.prefix(4), id: \.self) { stat in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.value)
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(stat.label)
                            .font(.system(size: 11, weight: .semibold))
                            .opacity(0.8)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            Spacer(minLength: 16)

            Text(verbatim: "Забони тоҷикиро меомӯзам!")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(mint)

            Spacer(minLength: 12)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Learn Tajik for free, even offline"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(AppLinks.displayURL)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .opacity(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                if let qrCode {
                    Image(uiImage: qrCode)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 58, height: 58)
                        .padding(5)
                        .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(
            LinearGradient(colors: [accent, deep], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .environment(\.colorScheme, .light)
    }
}

// MARK: - Rendering & sharing

/// PNG payload for ShareLink (explicit PNG so messengers keep full quality).
struct ShareCardImage: Transferable {
    let png: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
            .suggestedFileName("tajik-dictionary.png")
    }
}

@MainActor
enum ShareCardRenderer {
    static func render(_ content: ShareCardContent) -> (image: Image, payload: ShareCardImage)? {
        let renderer = ImageRenderer(content: ShareCardView(content: content, qrCode: qrCode(for: AppLinks.shareURL)))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(ShareCardView.size)
        guard let uiImage = renderer.uiImage, let png = uiImage.pngData() else { return nil }
        return (Image(uiImage: uiImage), ShareCardImage(png: png))
    }

    static func qrCode(for url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Share button: renders the card only when tapped, then shows a preview sheet with the system share button.
struct ShareCardButton: View {
    let content: ShareCardContent
    var title: String = String(localized: "Share result")
    var prominent: Bool = false

    @State private var presented: ShareCardContent?

    var body: some View {
        Button {
            presented = content
        } label: {
            Label(title, systemImage: "square.and.arrow.up")
                .frame(maxWidth: prominent ? .infinity : nil)
        }
        .sheet(item: $presented) { content in
            ShareCardSheet(content: content)
        }
    }
}

extension ShareCardContent: Identifiable {
    var id: Int { hashValue }
}

/// Preview of the card plus a ShareLink that sends PNG + text (both carry the app link).
struct ShareCardSheet: View {
    let content: ShareCardContent

    @Environment(\.dismiss) private var dismiss
    @State private var rendered: (image: Image, payload: ShareCardImage)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let rendered {
                    rendered.image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                        .padding(.horizontal, 24)
                        .accessibilityLabel(content.shareText)

                    ShareLink(
                        item: rendered.payload,
                        subject: Text(content.headline),
                        message: Text(content.shareText),
                        preview: SharePreview(content.headline, image: rendered.image)
                    ) {
                        Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 24)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Close")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task {
            rendered = ShareCardRenderer.render(content)
        }
    }
}

#Preview("Round card") {
    ShareCardView(
        content: .round(xp: 84, accuracy: 92, newWords: 6, streakDays: 5, cefr: "A2"),
        qrCode: ShareCardRenderer.qrCode(for: AppLinks.shareURL)
    )
}
