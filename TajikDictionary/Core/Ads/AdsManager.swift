import Foundation
@preconcurrency import GoogleMobileAds
import Observation
import UIKit
@preconcurrency import YandexMobileAds

/// Owns the ad lifecycle, mirroring the Android app's `AdsManager`:
/// consent first (Google UMP), then Yandex Mobile Ads and Google Mobile Ads (15 s cap).
/// Every slot is a waterfall: Yandex first, AdMob when Yandex fails or doesn't answer in 30 s,
/// guarded by the `AdsAvailability` circuit breaker. No ad is requested until `canShowAds` is true.
@MainActor
@Observable
final class AdsManager {
    static let shared = AdsManager()

    /// True once consent allows ad requests and both SDKs are initialized.
    /// Turned off while the privacy form is open, which removes every banner.
    private(set) var canShowAds = false
    /// Drives the "Privacy settings" row in Settings.
    private(set) var isPrivacyOptionsRequired = false
    /// Word detail screens on screen. While > 0 the tab banner uses the entry ad unit, so the
    /// detail screen gets its own unit without a second banner stacked on top of the tab's.
    var entryScreensVisible = 0

    private static let sdkInitTimeout: Duration = .seconds(15)
    /// Only hit if the privacy form's callback is genuinely lost (the user may be reading it).
    private static let privacyFormTimeout: Duration = .seconds(5 * 60)

    @ObservationIgnored private let availability = AdsAvailability.shared
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var sdksInitialized = false
    @ObservationIgnored private var privacyFormShowing = false

    // Interstitial
    @ObservationIgnored private var interstitial: LoadedInterstitial?
    @ObservationIgnored private var isLoadingInterstitial = false
    /// Bumped on every waterfall leg, so a late callback or timeout from an old leg is ignored.
    @ObservationIgnored private var interstitialLeg = 0
    @ObservationIgnored private var yandexLoader: InterstitialAdLoader?
    @ObservationIgnored private var yandexLoadHandler: YandexInterstitialLoadHandler?
    @ObservationIgnored private var interstitialDelegate: InterstitialDelegate?
    @ObservationIgnored private var roundsSinceInterstitial = 0
    @ObservationIgnored private var lastInterstitialAt: TimeInterval?

    private enum ReadyInterstitial {
        case yandex(YandexMobileAds.InterstitialAd)
        case admob(GoogleMobileAds.InterstitialAd)
    }

    private struct LoadedInterstitial {
        let ad: ReadyInterstitial
        let loadedAt: TimeInterval
    }

    private init() {}

    private var now: TimeInterval { AdsAvailability.monotonicNow() }

    // MARK: - Consent and SDKs

    /// Call once the first screen is on screen (after onboarding and the placement test on first launch).
    func start() async {
        guard AdConfig.isEnabled, !isStarting, !canShowAds, !privacyFormShowing else { return }
        isStarting = true
        defer { isStarting = false }

        // Fail closed until UMP has refreshed this session's consent. Never share device location.
        YandexAds.setLocationTracking(false)
        YandexAds.setUserConsent(false)

        _ = await ConsentManager.gatherConsent()
        await finishConsentFlow()
    }

    /// Settings → Privacy settings. Banners are torn down while the form is open, then the
    /// (possibly changed) choice is applied to both networks.
    func presentPrivacyOptions() async {
        guard !privacyFormShowing else { return }
        privacyFormShowing = true
        canShowAds = false
        let completed = await awaitWithTimeout(Self.privacyFormTimeout) {
            await ConsentManager.presentPrivacyOptions()
        }
        if !completed { Self.log("Privacy options form did not report back; resuming ads") }
        privacyFormShowing = false
        await finishConsentFlow()
    }

    private func finishConsentFlow() async {
        isPrivacyOptionsRequired = ConsentManager.isPrivacyOptionsRequired
        applyYandexConsent()
        guard AdConfig.isEnabled, ConsentManager.canRequestAds else {
            canShowAds = false
            return
        }
        await initializeSDKsIfNeeded()
        canShowAds = !privacyFormShowing && ConsentManager.canRequestAds
        if canShowAds { loadInterstitial() }
    }

    /// Yandex takes one boolean, derived from UMP's TCF values (purpose 1 + Additional Consent 1033
    /// where GDPR applies). Google's SDK reads the TCF values itself.
    private func applyYandexConsent() {
        let signals = TcfConsentSignals.from()
        YandexAds.setUserConsent(signals.allowsYandex(consentNotRequired: ConsentManager.isConsentNotRequired))
    }

    private func initializeSDKsIfNeeded() async {
        guard !sdksInitialized else { return }
        sdksInitialized = true
        let completed = await awaitWithTimeout(Self.sdkInitTimeout) {
            async let yandex: Void = Self.initializeYandex()
            async let google: Void = Self.initializeGoogle()
            _ = await (yandex, google)
        }
        // On timeout the SDKs keep starting in the background; requests made meanwhile are queued
        // or fail into the waterfall, which the breaker handles.
        if !completed { Self.log("Ad SDK initialization timed out; continuing") }
    }

    private static func initializeYandex() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            YandexAds.initializeSDK {
                continuation.resume()
            }
        }
    }

    private static func initializeGoogle() async {
        _ = await MobileAds.shared.start()
    }

    // MARK: - Interstitial

    /// Counts a finished game round and makes sure a fresh interstitial is ready for "Done".
    func recordFinishedRound() {
        roundsSinceInterstitial += 1
        loadInterstitial()
    }

    /// Shows an interstitial if one is due and loaded, then calls `completion` once it is closed
    /// (or right away when nothing is shown).
    func showInterstitialIfDue(then completion: @escaping @MainActor () -> Void) {
        let now = self.now
        guard canShowAds,
              let loaded = interstitial,
              InterstitialPacing.isFresh(loadedAt: loaded.loadedAt, now: now),
              InterstitialPacing.isDue(roundsSinceLast: roundsSinceInterstitial, lastShownAt: lastInterstitialAt, now: now),
              let presenter = UIApplication.topViewController() else {
            completion()
            return
        }
        let delegate = InterstitialDelegate { [weak self] in
            guard let self else { return }
            self.interstitialDelegate = nil
            self.loadInterstitial()
            completion()
        }
        interstitialDelegate = delegate
        interstitial = nil
        roundsSinceInterstitial = 0
        lastInterstitialAt = now
        switch loaded.ad {
        case .yandex(let ad):
            ad.delegate = delegate
            ad.show(from: presenter)
        case .admob(let ad):
            ad.fullScreenContentDelegate = delegate
            ad.present(from: presenter)
        }
    }

    /// Preloads the next interstitial: Yandex first (unless its breaker is open), then AdMob.
    private func loadInterstitial() {
        guard canShowAds, !isLoadingInterstitial else { return }
        if let interstitial, InterstitialPacing.isFresh(loadedAt: interstitial.loadedAt, now: now) { return }
        interstitial = nil
        guard availability.shouldTryAds else { return }
        isLoadingInterstitial = true
        if availability.shouldTryYandex {
            loadYandexInterstitial()
        } else {
            loadGoogleInterstitial()
        }
    }

    private func loadYandexInterstitial() {
        interstitialLeg += 1
        let leg = interstitialLeg
        let handler = YandexInterstitialLoadHandler(
            onLoaded: { [weak self] ad in self?.yandexInterstitialLoaded(ad, leg: leg) },
            onFailed: { [weak self] message in self?.yandexInterstitialFailed(message, leg: leg) }
        )
        let loader = InterstitialAdLoader()
        loader.delegate = handler
        yandexLoader = loader
        yandexLoadHandler = handler
        loader.loadAd(with: AdRequest(adUnitID: AdConfig.interstitial.yandex))
        scheduleLegTimeout(leg: leg) { [weak self] in
            self?.yandexInterstitialFailed("timed out", leg: leg)
        }
    }

    private func yandexInterstitialLoaded(_ ad: YandexMobileAds.InterstitialAd, leg: Int) {
        guard leg == interstitialLeg, isLoadingInterstitial else { return }
        availability.recordYandexSuccess()
        finishInterstitialLoad(.yandex(ad))
    }

    private func yandexInterstitialFailed(_ message: String, leg: Int) {
        guard leg == interstitialLeg, isLoadingInterstitial else { return }
        Self.log("Yandex interstitial failed, trying AdMob: \(message)")
        availability.recordYandexFailure()
        loadGoogleInterstitial()
    }

    private func loadGoogleInterstitial() {
        interstitialLeg += 1
        let leg = interstitialLeg
        GoogleMobileAds.InterstitialAd.load(with: AdConfig.interstitial.admob, request: Request()) { [weak self] ad, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let ad {
                    self.googleInterstitialLoaded(ad, leg: leg)
                } else {
                    self.googleInterstitialFailed(error?.localizedDescription ?? "no ad", leg: leg)
                }
            }
        }
        scheduleLegTimeout(leg: leg) { [weak self] in
            self?.googleInterstitialFailed("timed out", leg: leg)
        }
    }

    private func googleInterstitialLoaded(_ ad: GoogleMobileAds.InterstitialAd, leg: Int) {
        guard leg == interstitialLeg, isLoadingInterstitial else { return }
        availability.recordAdsSuccess()
        finishInterstitialLoad(.admob(ad))
    }

    private func googleInterstitialFailed(_ message: String, leg: Int) {
        guard leg == interstitialLeg, isLoadingInterstitial else { return }
        Self.log("AdMob interstitial failed: \(message)")
        availability.recordAdsFailure()
        interstitialLeg += 1
        isLoadingInterstitial = false
        yandexLoadHandler = nil
    }

    private func finishInterstitialLoad(_ ad: ReadyInterstitial) {
        interstitialLeg += 1
        isLoadingInterstitial = false
        yandexLoadHandler = nil
        interstitial = LoadedInterstitial(ad: ad, loadedAt: now)
    }

    private func scheduleLegTimeout(leg: Int, onTimeout: @escaping @MainActor () -> Void) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: InterstitialPacing.legTimeout)
            guard let self, self.interstitialLeg == leg, self.isLoadingInterstitial else { return }
            onTimeout()
        }
    }

    static func log(_ message: String) {
        #if DEBUG
        print("Ads: \(message)")
        #endif
    }
}

/// Runs `operation` but stops waiting after `timeout`; returns false on timeout.
/// The operation itself keeps running (SDK callbacks can't be cancelled); its late end is ignored.
@MainActor
func awaitWithTimeout(_ timeout: Duration, _ operation: @escaping @MainActor @Sendable () async -> Void) async -> Bool {
    let gate = ResumeOnce()
    return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        Task { @MainActor in
            await operation()
            if gate.claim() { continuation.resume(returning: true) }
        }
        Task { @MainActor in
            try? await Task.sleep(for: timeout)
            if gate.claim() { continuation.resume(returning: false) }
        }
    }
}

/// Lets exactly one of two racing tasks resume a continuation. Only touched on the main actor.
private final class ResumeOnce: @unchecked Sendable {
    private var claimed = false

    func claim() -> Bool {
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

/// Bridges Yandex's interstitial loader delegate to closures.
private final class YandexInterstitialLoadHandler: NSObject, InterstitialAdLoaderDelegate {
    private let onLoaded: @MainActor (YandexMobileAds.InterstitialAd) -> Void
    private let onFailed: @MainActor (String) -> Void

    init(
        onLoaded: @escaping @MainActor (YandexMobileAds.InterstitialAd) -> Void,
        onFailed: @escaping @MainActor (String) -> Void
    ) {
        self.onLoaded = onLoaded
        self.onFailed = onFailed
    }

    func interstitialAdLoader(_ adLoader: InterstitialAdLoader, didLoad interstitialAd: YandexMobileAds.InterstitialAd) {
        MainActor.assumeIsolated { onLoaded(interstitialAd) }
    }

    func interstitialAdLoader(_ adLoader: InterstitialAdLoader, didFailToLoadWithError error: AdRequestError) {
        let message = error.error.localizedDescription
        MainActor.assumeIsolated { onFailed(message) }
    }
}

/// Bridges Yandex and AdMob interstitial callbacks to a single "closed" closure.
private final class InterstitialDelegate: NSObject, InterstitialAdDelegate, FullScreenContentDelegate {
    private let onFinish: @MainActor () -> Void
    private var finished = false

    init(onFinish: @escaping @MainActor () -> Void) {
        self.onFinish = onFinish
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        MainActor.assumeIsolated { onFinish() }
    }

    // Yandex
    func interstitialAdDidDismiss(_ interstitialAd: YandexMobileAds.InterstitialAd) {
        finish()
    }

    func interstitialAd(_ interstitialAd: YandexMobileAds.InterstitialAd, didFailToShowWithError error: Error) {
        finish()
    }

    // AdMob
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        finish()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        finish()
    }
}
