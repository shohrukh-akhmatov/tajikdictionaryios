import XCTest
@testable import TajikDictionary

/// Mirrors the Android app's AdsAvailabilityTest, BannerWaterfallReducerTest,
/// TcfConsentSignalsTest and InterstitialPacingTest, so both platforms follow the same rules.
@MainActor
final class AdsAvailabilityTests: XCTestCase {
    // XCTest creates a new instance per test, so every test starts with a fresh breaker.
    private var clock: TimeInterval = 1_000
    private lazy var availability = AdsAvailability(now: { [unowned self] in self.clock })

    func testFreshStateTriesEverything() {
        XCTAssertTrue(availability.shouldTryYandex)
        XCTAssertTrue(availability.shouldTryAds)
    }

    func testFirstYandexFailureRetriesAfterTenSeconds() {
        availability.recordYandexFailure()
        XCTAssertFalse(availability.shouldTryYandex)
        clock += AdsAvailability.yandexBackoffRetry - 1
        XCTAssertFalse(availability.shouldTryYandex)
        clock += 1
        XCTAssertTrue(availability.shouldTryYandex)
    }

    func testYandexBackoffEscalatesAndCaps() {
        availability.recordYandexFailure()
        availability.recordYandexFailure()
        clock += AdsAvailability.yandexBackoffFirst - 1
        XCTAssertFalse(availability.shouldTryYandex)
        clock += 1
        XCTAssertTrue(availability.shouldTryYandex)

        availability.recordYandexFailure()
        clock += AdsAvailability.yandexBackoffMax - 1
        XCTAssertFalse(availability.shouldTryYandex)
        clock += 1
        XCTAssertTrue(availability.shouldTryYandex)

        availability.recordYandexFailure()
        clock += AdsAvailability.yandexBackoffMax - 1
        XCTAssertFalse(availability.shouldTryYandex, "stays at the longest back-off")
    }

    func testYandexSuccessResetsEscalation() {
        availability.recordYandexFailure()
        availability.recordYandexFailure()
        availability.recordYandexSuccess()
        XCTAssertTrue(availability.shouldTryYandex)
        availability.recordYandexFailure()
        clock += AdsAvailability.yandexBackoffRetry
        XCTAssertTrue(availability.shouldTryYandex, "back to the short retry")
    }

    func testYandexFailuresDoNotCloseAdsBreaker() {
        for _ in 0..<10 { availability.recordYandexFailure() }
        XCTAssertTrue(availability.shouldTryAds)
    }

    func testAdsBreakerOpensAfterThreeFailuresForSixHours() {
        availability.recordAdsFailure()
        availability.recordAdsFailure()
        XCTAssertTrue(availability.shouldTryAds)
        availability.recordAdsFailure()
        XCTAssertFalse(availability.shouldTryAds)
        clock += AdsAvailability.adsCooldown - 1
        XCTAssertFalse(availability.shouldTryAds)
        clock += 1
        XCTAssertTrue(availability.shouldTryAds)
    }

    func testAdsSuccessResetsFailureCount() {
        availability.recordAdsFailure()
        availability.recordAdsFailure()
        availability.recordAdsSuccess()
        availability.recordAdsFailure()
        availability.recordAdsFailure()
        XCTAssertTrue(availability.shouldTryAds)
    }

    func testYandexSuccessAlsoResetsAdsFailures() {
        availability.recordAdsFailure()
        availability.recordAdsFailure()
        availability.recordYandexSuccess()
        availability.recordAdsFailure()
        XCTAssertTrue(availability.shouldTryAds)
    }
}

final class BannerWaterfallTests: XCTestCase {
    private let reduce = BannerWaterfall.reduce

    func testStartsAtYandexOrSkipsToGoogle() {
        XCTAssertEqual(BannerWaterfallState.initial(tryYandex: true), BannerWaterfallState(provider: .yandex, attemptId: 0))
        XCTAssertEqual(BannerWaterfallState.initial(tryYandex: false), BannerWaterfallState(provider: .google, attemptId: 1))
    }

    func testYandexLoadMarksLoaded() {
        let next = reduce(BannerWaterfallState(), .yandexLoaded(attemptId: 0))
        XCTAssertEqual(next, BannerWaterfallState(provider: .yandex, attemptId: 0, loaded: true))
    }

    func testYandexFailureMovesToGoogle() {
        XCTAssertEqual(reduce(BannerWaterfallState(), .yandexFailed(attemptId: 0)), BannerWaterfallState(provider: .google, attemptId: 1))
    }

    func testYandexTimeoutMovesToGoogle() {
        XCTAssertEqual(reduce(BannerWaterfallState(), .yandexTimedOut(attemptId: 0)), BannerWaterfallState(provider: .google, attemptId: 1))
    }

    func testLateYandexCallbackIsIgnoredAfterMovingOn() {
        let google = BannerWaterfallState(provider: .google, attemptId: 1)
        XCTAssertEqual(reduce(google, .yandexLoaded(attemptId: 0)), google)
        XCTAssertEqual(reduce(google, .yandexFailed(attemptId: 0)), google)
    }

    func testGoogleLoadMarksLoaded() {
        let google = BannerWaterfallState(provider: .google, attemptId: 1)
        XCTAssertEqual(reduce(google, .googleLoaded(attemptId: 1)), BannerWaterfallState(provider: .google, attemptId: 1, loaded: true))
    }

    func testGoogleFailureExhausts() {
        let google = BannerWaterfallState(provider: .google, attemptId: 1)
        XCTAssertEqual(reduce(google, .googleFailed(attemptId: 1)), BannerWaterfallState(provider: .exhausted, attemptId: 2))
        XCTAssertEqual(reduce(google, .googleTimedOut(attemptId: 1)), BannerWaterfallState(provider: .exhausted, attemptId: 2))
    }

    func testTimeoutAfterLoadIsIgnored() {
        let loaded = BannerWaterfallState(provider: .yandex, attemptId: 0, loaded: true)
        XCTAssertEqual(reduce(loaded, .yandexTimedOut(attemptId: 0)), loaded)
        let googleLoaded = BannerWaterfallState(provider: .google, attemptId: 1, loaded: true)
        XCTAssertEqual(reduce(googleLoaded, .googleTimedOut(attemptId: 1)), googleLoaded)
    }

    func testEventForOtherProviderWithSameAttemptIsIgnored() {
        let yandex = BannerWaterfallState()
        XCTAssertEqual(reduce(yandex, .googleLoaded(attemptId: 0)), yandex)
        XCTAssertEqual(reduce(yandex, .googleFailed(attemptId: 0)), yandex)
    }

    func testExhaustedIsTerminal() {
        let exhausted = BannerWaterfallState(provider: .exhausted, attemptId: 2)
        XCTAssertEqual(reduce(exhausted, .googleLoaded(attemptId: 2)), exhausted)
        XCTAssertEqual(reduce(exhausted, .yandexLoaded(attemptId: 2)), exhausted)
    }
}

final class TcfConsentSignalsTests: XCTestCase {
    private let allPurposes = String(repeating: "1", count: 11)

    func testOutsideGdprAllowsEverything() {
        let signals = TcfConsentSignals(gdprApplies: 0, purposeConsents: nil, additionalConsent: nil)
        XCTAssertTrue(signals.allowsStorage(consentNotRequired: false))
        XCTAssertTrue(signals.allowsYandex(consentNotRequired: false))
        XCTAssertTrue(signals.allowsPersonalization(consentNotRequired: false))
    }

    func testUnknownGdprFollowsUmpStatus() {
        let signals = TcfConsentSignals(gdprApplies: nil, purposeConsents: nil, additionalConsent: nil)
        XCTAssertFalse(signals.allowsYandex(consentNotRequired: false))
        XCTAssertTrue(signals.allowsYandex(consentNotRequired: true))
        XCTAssertFalse(signals.allowsPersonalization(consentNotRequired: false))
        XCTAssertTrue(signals.allowsPersonalization(consentNotRequired: true))
    }

    func testGdprFullConsentWithYandexInAdditionalConsent() {
        let signals = TcfConsentSignals(gdprApplies: 1, purposeConsents: allPurposes, additionalConsent: "2~89.1033.2211~dv.")
        XCTAssertTrue(signals.allowsYandex(consentNotRequired: false))
        XCTAssertTrue(signals.allowsPersonalization(consentNotRequired: false))
    }

    func testGdprWithoutYandexAdditionalConsentBlocksYandexOnly() {
        let signals = TcfConsentSignals(gdprApplies: 1, purposeConsents: allPurposes, additionalConsent: "2~89.2211~dv.1033")
        XCTAssertFalse(signals.allowsYandex(consentNotRequired: false), "1033 only in the disclosed list")
        XCTAssertTrue(signals.allowsStorage(consentNotRequired: false))
    }

    func testGdprWithoutPurposeOneBlocksEverything() {
        let signals = TcfConsentSignals(gdprApplies: 1, purposeConsents: "0111111111", additionalConsent: "2~1033~dv.")
        XCTAssertFalse(signals.allowsStorage(consentNotRequired: false))
        XCTAssertFalse(signals.allowsYandex(consentNotRequired: false))
        XCTAssertFalse(signals.allowsPersonalization(consentNotRequired: false))
    }

    func testGdprStorageOnlyIsNonPersonalized() {
        let signals = TcfConsentSignals(gdprApplies: 1, purposeConsents: "1100000000", additionalConsent: "2~1033~dv.")
        XCTAssertTrue(signals.allowsYandex(consentNotRequired: false))
        XCTAssertFalse(signals.allowsPersonalization(consentNotRequired: false))
    }

    func testReadsUmpValuesFromUserDefaults() throws {
        let suite = "TcfConsentSignalsTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1, forKey: "IABTCF_gdprApplies")
        defaults.set("1011", forKey: "IABTCF_PurposeConsents")
        defaults.set("2~1033~dv.", forKey: "IABTCF_AddtlConsent")
        XCTAssertEqual(
            TcfConsentSignals.from(defaults),
            TcfConsentSignals(gdprApplies: 1, purposeConsents: "1011", additionalConsent: "2~1033~dv.")
        )
    }
}

final class InterstitialPacingTests: XCTestCase {
    func testNeedsEnoughRounds() {
        XCTAssertFalse(InterstitialPacing.isDue(roundsSinceLast: AdConfig.roundsBetweenInterstitials - 1, lastShownAt: nil, now: 0))
        XCTAssertTrue(InterstitialPacing.isDue(roundsSinceLast: AdConfig.roundsBetweenInterstitials, lastShownAt: nil, now: 0))
    }

    func testRespectsMinimumGap() {
        let rounds = AdConfig.roundsBetweenInterstitials
        let gap = AdConfig.minSecondsBetweenInterstitials
        XCTAssertFalse(InterstitialPacing.isDue(roundsSinceLast: rounds, lastShownAt: 100, now: 100 + gap - 1))
        XCTAssertTrue(InterstitialPacing.isDue(roundsSinceLast: rounds, lastShownAt: 100, now: 100 + gap))
    }

    func testLoadedAdGoesStaleAfter55Minutes() {
        XCTAssertTrue(InterstitialPacing.isFresh(loadedAt: 0, now: 55 * 60 - 1))
        XCTAssertFalse(InterstitialPacing.isFresh(loadedAt: 0, now: 55 * 60))
    }
}
