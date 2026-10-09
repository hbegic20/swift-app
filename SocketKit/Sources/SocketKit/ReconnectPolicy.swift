import Foundation

/// Growing delays between reconnect attempts: 1s, 2s, 4s, ... up to 30s,
/// each with about 20 percent random jitter (rule 7).
public struct ReconnectPolicy: Equatable, Sendable {
    public var baseDelay: TimeInterval
    public var maxDelay: TimeInterval
    /// 0.2 means the delay lands somewhere between 80% and 120% of the base.
    public var jitter: Double

    public static let standard = ReconnectPolicy(baseDelay: 1, maxDelay: 30, jitter: 0.2)

    public init(baseDelay: TimeInterval, maxDelay: TimeInterval, jitter: Double) {
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitter = jitter
    }

    /// - Parameters:
    ///   - attempt: 0 for the first retry after a failure.
    ///   - random: a number in 0...1. 0.5 means no jitter. Passed in so tests get fixed results.
    public func delay(forAttempt attempt: Int, random: Double) -> TimeInterval {
        // Clamp the exponent so huge attempt counts cannot overflow.
        let exponent = Double(min(max(attempt, 0), 30))
        let base = min(maxDelay, baseDelay * pow(2, exponent))
        let clampedRandom = min(max(random, 0), 1)
        return base * (1 + jitter * (2 * clampedRandom - 1))
    }
}
