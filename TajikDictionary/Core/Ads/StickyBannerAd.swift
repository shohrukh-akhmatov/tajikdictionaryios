import Combine
@preconcurrency import GoogleMobileAds
import SwiftUI
import UIKit
@preconcurrency import YandexMobileAds

/// A banner pinned to the bottom of the screen with the same Yandex → Google waterfall as the
/// Android app's `PinnedBanner`:
///
/// - One network view at a time; each leg gets 30 s before the waterfall moves on.
/// - Skips straight to Google while the Yandex breaker is open, and shows nothing while the
///   whole-ads breaker is open (`AdsAvailability`).
/// - Takes no height until a creative has loaded, so an offline user never sees an empty strip.
///   When both networks fail it stays collapsed for the rest of this screen visit.
/// - Hidden while the keyboard is up, so it never sits between the text field and the keys.
/// - Switches to the word-detail ad unit while a word detail screen is pushed in this tab.
struct StickyBannerAd: View {
    private let ads = AdsManager.shared
    @State private var keyboardVisible = false

    var body: some View {
        VStack(spacing: 0) {
            if ads.canShowAds, !keyboardVisible, AdsAvailability.shared.shouldTryAds {
                let isEntry = ads.entryScreensVisible > 0
                WaterfallBannerSlot(slot: isEntry ? AdConfig.entryBanner : AdConfig.banner)
                    .id(isEntry) // fresh waterfall when the ad unit changes
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
    }
}

private struct WaterfallBannerSlot: View {
    let slot: AdConfig.Slot

    @State private var width = 0
    @State private var waterfall = BannerWaterfallState.initial(tryYandex: AdsAvailability.shared.shouldTryYandex)
    @State private var loadedHeight: CGFloat = 0

    private static let minWidth = 32

    var body: some View {
        ZStack(alignment: .top) {
            if width >= Self.minWidth, waterfall.provider != .exhausted {
                BannerHost(
                    provider: waterfall.provider,
                    slot: slot,
                    width: CGFloat(width),
                    attemptId: waterfall.attemptId,
                    onEvent: handle,
                    onHeight: { loadedHeight = $0 }
                )
                // A new provider view for every leg and every width.
                .id(LegKey(provider: waterfall.provider, attemptId: waterfall.attemptId, width: width))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: waterfall.loaded ? loadedHeight : 0, alignment: .top)
        .clipped()
        .background(AppTheme.background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Advertisement"))
        .onGeometryChange(for: Int.self) { proxy in
            Int(proxy.size.width.rounded())
        } action: { newWidth in
            guard newWidth != width else { return }
            width = newWidth
            // Rotation or a resized window: start the waterfall over at the new width.
            waterfall = .initial(tryYandex: AdsAvailability.shared.shouldTryYandex)
            loadedHeight = 0
        }
        .task(id: LegKey(provider: waterfall.provider, attemptId: waterfall.attemptId, width: waterfall.loaded ? -1 : width)) {
            guard !waterfall.loaded, width >= Self.minWidth else { return }
            let attemptId = waterfall.attemptId
            do {
                try await Task.sleep(for: BannerWaterfall.legTimeout)
            } catch {
                return // the leg ended (loaded, failed, or the view went away)
            }
            switch waterfall.provider {
            case .yandex:
                AdsManager.log("Yandex banner timed out")
                handle(.yandexTimedOut(attemptId: attemptId))
            case .google:
                AdsManager.log("AdMob banner timed out")
                handle(.googleTimedOut(attemptId: attemptId))
            case .exhausted:
                break
            }
        }
    }

    private func handle(_ event: BannerWaterfallEvent) {
        let previous = waterfall
        let next = BannerWaterfall.reduce(previous, event)
        guard next != previous else { return }
        let availability = AdsAvailability.shared
        switch event {
        case .yandexLoaded: availability.recordYandexSuccess()
        case .googleLoaded: availability.recordAdsSuccess()
        case .yandexFailed, .yandexTimedOut: availability.recordYandexFailure()
        case .googleFailed, .googleTimedOut: break
        }
        if next.provider == .exhausted { availability.recordAdsFailure() }
        waterfall = next
    }
}

private struct LegKey: Hashable {
    let provider: BannerProvider
    let attemptId: Int
    let width: Int
}

/// Hosts exactly one network's banner view for one waterfall leg.
private struct BannerHost: UIViewRepresentable {
    let provider: BannerProvider
    let slot: AdConfig.Slot
    let width: CGFloat
    let attemptId: Int
    let onEvent: @MainActor (BannerWaterfallEvent) -> Void
    let onHeight: @MainActor (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(attemptId: attemptId, onEvent: onEvent, onHeight: onHeight)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        let coordinator = context.coordinator
        switch provider {
        case .yandex:
            let view = BannerAdView(adSize: BannerAdSize.sticky(containerWidth: width))
            view.delegate = coordinator
            install(view, in: container)
            view.loadAd(with: AdRequest(adUnitID: slot.yandex))
        case .google:
            let view = BannerView(adSize: largeAnchoredAdaptiveBanner(width: width))
            view.adUnitID = slot.admob
            view.rootViewController = UIApplication.topViewController()
            view.delegate = coordinator
            install(view, in: container)
            view.load(Request())
        case .exhausted:
            break
        }
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        context.coordinator.onEvent = onEvent
        context.coordinator.onHeight = onHeight
    }

    static func dismantleUIView(_ container: UIView, coordinator: Coordinator) {
        coordinator.isActive = false
        container.subviews.forEach { $0.removeFromSuperview() }
    }

    private func install(_ view: UIView, in container: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
        ])
    }

    @MainActor
    final class Coordinator: NSObject, BannerAdViewDelegate, BannerViewDelegate {
        var onEvent: @MainActor (BannerWaterfallEvent) -> Void
        var onHeight: @MainActor (CGFloat) -> Void
        var isActive = true
        private let attemptId: Int

        init(
            attemptId: Int,
            onEvent: @escaping @MainActor (BannerWaterfallEvent) -> Void,
            onHeight: @escaping @MainActor (CGFloat) -> Void
        ) {
            self.attemptId = attemptId
            self.onEvent = onEvent
            self.onHeight = onHeight
        }

        private func send(_ event: BannerWaterfallEvent, height: CGFloat? = nil) {
            guard isActive else { return }
            if let height { onHeight(height) }
            onEvent(event)
        }

        // Yandex
        nonisolated func bannerAdViewDidLoad(_ adView: BannerAdView) {
            MainActor.assumeIsolated {
                send(.yandexLoaded(attemptId: attemptId), height: adView.adSize.size.height)
            }
        }

        nonisolated func bannerAdViewDidFailLoading(_ adView: BannerAdView, error: Error) {
            let message = error.localizedDescription
            MainActor.assumeIsolated {
                AdsManager.log("Yandex banner failed: \(message)")
                send(.yandexFailed(attemptId: attemptId))
            }
        }

        // AdMob
        nonisolated func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            MainActor.assumeIsolated {
                send(.googleLoaded(attemptId: attemptId), height: bannerView.adSize.size.height)
            }
        }

        nonisolated func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            let message = error.localizedDescription
            MainActor.assumeIsolated {
                AdsManager.log("AdMob banner failed: \(message)")
                send(.googleFailed(attemptId: attemptId))
            }
        }
    }
}

extension View {
    /// Pins the waterfall banner to the bottom of a screen (above the tab bar in a tab), covering
    /// the screens pushed in it.
    func stickyBannerAd() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            StickyBannerAd()
        }
    }
}
