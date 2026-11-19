import Foundation

/// Ad unit IDs and frequency rules, mirroring the Android app's `Config/AdUnits.properties`.
///
/// Waterfall per slot: Yandex first, Google AdMob as the fallback.
/// Debug builds always use the Yandex demo units and Google's test units.
/// Release builds keep ads OFF until every production ID below is filled in.
///
/// TODO before release:
/// - Yandex IDs from https://partner.yandex.ru (Ad units → Mobile apps), AdMob IDs from the AdMob console.
/// - Replace `GADApplicationIdentifier` in Config/TajikDictionary-Info.plist with the real AdMob app ID
///   and publish a GDPR message in AdMob → Privacy & messaging (UMP shows no form without one).
enum AdConfig {
    struct Slot: Sendable {
        let yandex: String
        let admob: String
    }

    private static let production = (
        banner: Slot(yandex: "", admob: ""),
        entryBanner: Slot(yandex: "", admob: ""),
        interstitial: Slot(yandex: "", admob: "")
    )

    private static let test = (
        banner: Slot(yandex: "demo-banner-yandex", admob: "ca-app-pub-3940256099942544/2435281174"),
        entryBanner: Slot(yandex: "demo-banner-yandex", admob: "ca-app-pub-3940256099942544/2435281174"),
        interstitial: Slot(yandex: "demo-interstitial-yandex", admob: "ca-app-pub-3940256099942544/4411468910")
    )

    #if DEBUG
    static let isEnabled = true
    /// Pinned bottom banner on every screen except Settings and onboarding (tabs, word game, level test).
    static let banner = test.banner
    /// Pinned bottom banner on the word detail screen (separate unit so its revenue is reported apart).
    static let entryBanner = test.entryBanner
    /// Interstitial when leaving the word game.
    static let interstitial = test.interstitial
    /// Set to true to see the GDPR form on the simulator as if you were in the EEA.
    static let debugForceEEA = false
    #else
    static let isEnabled = [production.banner, production.entryBanner, production.interstitial]
        .allSatisfy { !$0.yandex.isEmpty && !$0.admob.isEmpty }
    static let banner = production.banner
    static let entryBanner = production.entryBanner
    static let interstitial = production.interstitial
    #endif

    /// Show an interstitial after every Nth finished game round…
    static let roundsBetweenInterstitials = 3
    /// …and never more often than this.
    static let minSecondsBetweenInterstitials: TimeInterval = 180
}
