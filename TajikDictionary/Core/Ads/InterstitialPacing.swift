import Foundation

/// When a word-game interstitial may be shown. Same rules as the Android app: only after
/// `AdConfig.roundsBetweenInterstitials` finished rounds, and never twice within
/// `AdConfig.minSecondsBetweenInterstitials`. A loaded ad is dropped after 55 minutes (Google
/// expires them at one hour).
enum InterstitialPacing {
    static let legTimeout: Duration = .seconds(30)
    static let maxAge: TimeInterval = 55 * 60

    static func isDue(roundsSinceLast: Int, lastShownAt: TimeInterval?, now: TimeInterval) -> Bool {
        guard roundsSinceLast >= AdConfig.roundsBetweenInterstitials else { return false }
        guard let lastShownAt else { return true }
        return now - lastShownAt >= AdConfig.minSecondsBetweenInterstitials
    }

    static func isFresh(loadedAt: TimeInterval, now: TimeInterval) -> Bool {
        now - loadedAt < maxAge
    }
}
