import Foundation

enum ReviewRating: Int, Sendable {
    case again = 1
    case good = 4
    case easy = 5
}

struct FlashcardState: Sendable {
    var repetitions: Int = 0
    var intervalDays: Int = 0
    var easeFactor: Double = 2.5
}

/// Pure SM-2 spaced-repetition scheduler shared in design between iOS and Android.
enum FlashcardScheduler {
    private static let daySeconds: TimeInterval = 86_400

    static func next(
        current: FlashcardState,
        rating: ReviewRating,
        now: Date = .now
    ) -> (state: FlashcardState, nextReviewAt: Date) {
        let q = rating.rawValue
        let nextEf = max(
            1.3,
            current.easeFactor + (0.1 - Double(5 - q) * (0.08 + Double(5 - q) * 0.02))
        )
        if q < 3 {
            let state = FlashcardState(repetitions: 0, intervalDays: 0, easeFactor: nextEf)
            return (state, now.addingTimeInterval(600))
        } else {
            let reps = current.repetitions + 1
            let interval: Int
            switch reps {
            case 1: interval = 1
            case 2: interval = 6
            default: interval = max(1, Int((Double(current.intervalDays) * nextEf).rounded()))
            }
            let boosted = (rating == .easy && reps == 1) ? 3 : interval
            let state = FlashcardState(repetitions: reps, intervalDays: boosted, easeFactor: nextEf)
            return (state, now.addingTimeInterval(Double(boosted) * daySeconds))
        }
    }
}
