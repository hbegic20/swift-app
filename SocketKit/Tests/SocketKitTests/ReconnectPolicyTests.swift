import Testing
@testable import SocketKit

// Rule 7: 1s, 2s, 4s, up to 30s, with about 20 percent jitter.
@Suite("Reconnect policy")
struct ReconnectPolicyTests {
    let policy = ReconnectPolicy.standard

    @Test func doublesUpToThirtySeconds() {
        let delays = (0..<8).map { policy.delay(forAttempt: $0, random: 0.5) }
        #expect(delays == [1, 2, 4, 8, 16, 30, 30, 30])
    }

    @Test func jitterIsAboutTwentyPercent() {
        #expect(abs(policy.delay(forAttempt: 2, random: 0) - 3.2) < 0.0001)
        #expect(abs(policy.delay(forAttempt: 2, random: 1) - 4.8) < 0.0001)
    }

    @Test func randomOutsideRangeIsClamped() {
        #expect(policy.delay(forAttempt: 0, random: -5) == policy.delay(forAttempt: 0, random: 0))
        #expect(policy.delay(forAttempt: 0, random: 7) == policy.delay(forAttempt: 0, random: 1))
    }

    @Test func hugeAttemptCountDoesNotOverflow() {
        #expect(policy.delay(forAttempt: 10_000, random: 0.5) == 30)
    }
}
