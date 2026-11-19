import Foundation

/// The banner waterfall as a pure reducer, same as the Android app's `reduceBannerWaterfall`.
///
/// Every leg has an `attemptId`. Moving to the next leg bumps it, so a late callback or timeout
/// from an earlier leg (a Yandex "loaded" arriving after we already gave up on it) can never
/// touch the current one.
enum BannerProvider: Sendable, Equatable {
    case yandex, google, exhausted
}

struct BannerWaterfallState: Sendable, Equatable {
    var provider: BannerProvider = .yandex
    var attemptId = 0
    var loaded = false

    /// Starts at Google (attempt 1, the id the Yandex leg would have advanced to) when the
    /// Yandex breaker is open, so it doesn't pay a full Yandex timeout first.
    static func initial(tryYandex: Bool) -> BannerWaterfallState {
        tryYandex ? BannerWaterfallState() : BannerWaterfallState(provider: .google, attemptId: 1)
    }
}

enum BannerWaterfallEvent: Sendable, Equatable {
    case yandexLoaded(attemptId: Int)
    case yandexFailed(attemptId: Int)
    case yandexTimedOut(attemptId: Int)
    case googleLoaded(attemptId: Int)
    case googleFailed(attemptId: Int)
    case googleTimedOut(attemptId: Int)

    var attemptId: Int {
        switch self {
        case .yandexLoaded(let id), .yandexFailed(let id), .yandexTimedOut(let id),
             .googleLoaded(let id), .googleFailed(let id), .googleTimedOut(let id):
            return id
        }
    }
}

enum BannerWaterfall {
    /// How long one network gets to answer before the waterfall moves on.
    static let legTimeout: Duration = .seconds(30)

    static func reduce(_ state: BannerWaterfallState, _ event: BannerWaterfallEvent) -> BannerWaterfallState {
        guard event.attemptId == state.attemptId else { return state }
        switch event {
        case .yandexLoaded:
            guard state.provider == .yandex else { return state }
            var next = state
            next.loaded = true
            return next
        case .yandexFailed, .yandexTimedOut:
            guard state.provider == .yandex, !state.loaded else { return state }
            return BannerWaterfallState(provider: .google, attemptId: state.attemptId + 1)
        case .googleLoaded:
            guard state.provider == .google else { return state }
            var next = state
            next.loaded = true
            return next
        case .googleFailed, .googleTimedOut:
            guard state.provider == .google, !state.loaded else { return state }
            return BannerWaterfallState(provider: .exhausted, attemptId: state.attemptId + 1)
        }
    }
}
