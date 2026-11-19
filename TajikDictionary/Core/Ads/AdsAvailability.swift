import Foundation

/// App-wide circuit breaker for the ad waterfall (Yandex → Google), same rules as the Android app.
///
/// Every screen change remounts the pinned banner. Without a back-off, each remount re-opens a
/// doomed request on a network whose answer the app already knows, and each one pays its own
/// full-length timeout before moving on. Two independent, escalating cooldowns stop that:
///
/// - Yandex leg: the first failure retries shortly (10 s), a second consecutive failure backs off
///   for 5 min, anything beyond for 15 min, so Google still runs in the meantime.
///   A Yandex success resets the escalation.
/// - Whole waterfall: after 3 consecutive placements where both networks failed, ads are skipped
///   entirely for 6 h. A success from either network resets it.
@MainActor
final class AdsAvailability {
    static let shared = AdsAvailability()

    nonisolated static let yandexBackoffRetry: TimeInterval = 10
    nonisolated static let yandexBackoffFirst: TimeInterval = 5 * 60
    nonisolated static let yandexBackoffMax: TimeInterval = 15 * 60
    nonisolated static let adsFailureThreshold = 3
    nonisolated static let adsCooldown: TimeInterval = 6 * 60 * 60

    private var yandexFailures = 0
    private var yandexCooldownUntil: TimeInterval = 0
    private var adsFailures = 0
    private var adsCooldownUntil: TimeInterval = 0

    /// Monotonic seconds that keep counting while the device sleeps. Injectable for tests.
    private let now: () -> TimeInterval

    init(now: @escaping () -> TimeInterval = AdsAvailability.monotonicNow) {
        self.now = now
    }

    nonisolated static func monotonicNow() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }

    /// False while the Yandex breaker is open; callers should start at Google.
    var shouldTryYandex: Bool { now() >= yandexCooldownUntil }

    /// False while the ads breaker is open; callers should skip the slot entirely.
    var shouldTryAds: Bool { now() >= adsCooldownUntil }

    func recordYandexSuccess() {
        yandexFailures = 0
        yandexCooldownUntil = 0
        recordAdsSuccess()
    }

    func recordAdsSuccess() {
        adsFailures = 0
        adsCooldownUntil = 0
    }

    func recordYandexFailure() {
        yandexFailures += 1
        let backoff: TimeInterval = switch yandexFailures {
        case 1: Self.yandexBackoffRetry
        case 2: Self.yandexBackoffFirst
        default: Self.yandexBackoffMax
        }
        yandexCooldownUntil = now() + backoff
    }

    func recordAdsFailure() {
        adsFailures += 1
        if adsFailures >= Self.adsFailureThreshold {
            adsFailures = 0
            adsCooldownUntil = now() + Self.adsCooldown
        }
    }
}
