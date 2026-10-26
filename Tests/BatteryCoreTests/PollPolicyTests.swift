import Foundation
import Testing
@testable import BatteryCore

@Suite("Poll policy")
struct PollPolicyTests {
    let policy = PollPolicy()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let allTriggers: [PollTrigger] = [.launch, .dongleArrived, .timer, .menuOpened, .refreshNow, .didWake]

    func reading(charging: Bool?) -> Reading {
        Reading(level: 74, charging: charging, at: now)!
    }

    func pollAfter(_ trigger: PollTrigger, lastAttempt: Date? = nil) -> TimeInterval? {
        policy.decide(trigger, dongle: true, inFlight: false, lastAttempt: lastAttempt, now: now).pollAfter
    }

    @Test func noPollWithoutDongle() {
        for trigger in allTriggers {
            #expect(policy.decide(trigger, dongle: false, inFlight: false, lastAttempt: nil, now: now).pollAfter == nil)
        }
    }

    @Test func noPollWhileInFlight() {
        for trigger in allTriggers {
            #expect(policy.decide(trigger, dongle: true, inFlight: true, lastAttempt: nil, now: now).pollAfter == nil)
        }
    }

    @Test func launchAndArrivalWait() {
        #expect(pollAfter(.launch) == 1.5)
        #expect(pollAfter(.dongleArrived) == 1.5)
    }

    @Test func wakeWaits() {
        #expect(pollAfter(.didWake) == 5)
    }

    @Test func menuOpenIsThrottled() {
        #expect(pollAfter(.menuOpened) == 0)
        #expect(pollAfter(.menuOpened, lastAttempt: now.addingTimeInterval(-59)) == nil)
        #expect(pollAfter(.menuOpened, lastAttempt: now.addingTimeInterval(-61)) == 0)
    }

    @Test func refreshNowAndTimerPollAtOnce() {
        #expect(pollAfter(.refreshNow, lastAttempt: now) == 0)
        #expect(pollAfter(.timer, lastAttempt: now) == 0)
    }

    @Test func nextTimer() {
        #expect(policy.nextTimer(after: .ok(reading(charging: true))) == 120)
        #expect(policy.nextTimer(after: .ok(reading(charging: false))) == 300)
        #expect(policy.nextTimer(after: .ok(reading(charging: nil))) == 300)
        #expect(policy.nextTimer(after: .headsetOff(last: reading(charging: true))) == 300)
        #expect(policy.nextTimer(after: .problem("x", last: nil)) == 300)
    }

    @Test func retryableFailures() {
        #expect(policy.isRetryable(.openFailed(.busy), donglePresent: true))
        #expect(policy.isRetryable(.openFailed(.other(5)), donglePresent: true))
        #expect(policy.isRetryable(.noDongle, donglePresent: true))
        #expect(!policy.isRetryable(.noDongle, donglePresent: false))
        #expect(!policy.isRetryable(.openFailed(.notPermitted), donglePresent: true))
        #expect(!policy.isRetryable(.noReply, donglePresent: true))
        #expect(!policy.isRetryable(.badReply(200), donglePresent: true))
        #expect(!policy.isRetryable(.reading(reading(charging: false)), donglePresent: true))
    }

    @Test func consecutiveFailuresCountAndReset() {
        let busy = ReadOutcome.openFailed(.busy)
        #expect(policy.consecutiveFailures(after: busy, donglePresent: true, previous: 0) == 1)
        #expect(policy.consecutiveFailures(after: busy, donglePresent: true, previous: 2) == 3)
        #expect(policy.consecutiveFailures(after: .noReply, donglePresent: true, previous: 2) == 0)
        #expect(policy.consecutiveFailures(after: .reading(reading(charging: false)), donglePresent: true, previous: 3) == 0)
    }

    @Test func problemsRetrySoonThenBackOff() {
        let busy = ReadOutcome.openFailed(.busy)
        let state = HeadsetState.starting.applying(busy)
        var failures = 0
        var timers: [TimeInterval] = []
        for _ in 0..<5 {
            failures = policy.consecutiveFailures(after: busy, donglePresent: true, previous: failures)
            timers.append(policy.nextTimer(after: busy, state: state, donglePresent: true, failures: failures))
        }
        #expect(timers == [20, 20, 20, 300, 300])

        // No device object although the monitor still sees the dongle.
        #expect(policy.nextTimer(after: .noDongle, state: .noDongle, donglePresent: true, failures: 1) == 20)
        #expect(policy.nextTimer(after: .openFailed(.other(5)), state: state, donglePresent: true, failures: 1) == 20)
    }

    @Test func headsetOffKeepsNormalInterval() {
        let off = HeadsetState.headsetOff(last: nil)
        #expect(policy.nextTimer(after: .noReply, state: off, donglePresent: true, failures: 0) == 300)
        let notPermitted = HeadsetState.starting.applying(.openFailed(.notPermitted))
        #expect(policy.nextTimer(after: .openFailed(.notPermitted), state: notPermitted, donglePresent: true, failures: 0) == 300)
        let charging = HeadsetState.ok(reading(charging: true))
        #expect(policy.nextTimer(after: .reading(reading(charging: true)), state: charging, donglePresent: true, failures: 0) == 120)
    }

    @Test func intervalOverrideIsClamped() {
        #expect(PollPolicy.withIntervalOverride(nil).interval == 300)
        #expect(PollPolicy.withIntervalOverride(10).interval == 30)
        #expect(PollPolicy.withIntervalOverride(90).interval == 90)
        #expect(PollPolicy.withIntervalOverride(90).chargingInterval == 120)
    }

    @Test func stateKeepsLastReadingThroughNoReply() {
        let good = reading(charging: false)
        let ok = HeadsetState.starting.applying(.reading(good))
        #expect(ok == .ok(good))

        let off = ok.applying(.noReply)
        #expect(off == .headsetOff(last: good))
        #expect(off.applying(.noReply) == .headsetOff(last: good))

        let busy = off.applying(.openFailed(.busy))
        #expect(busy.lastReading == good)
        #expect(busy.applying(.badReply(200)).lastReading == good)

        #expect(off.applying(.noDongle) == .noDongle)
    }

    @Test func rememberedReadingFillsGap() {
        let remembered = reading(charging: nil)
        #expect(HeadsetState.noDongle.applying(.noReply).remembering(remembered) == .headsetOff(last: remembered))
        let newer = reading(charging: true)
        #expect(HeadsetState.headsetOff(last: newer).remembering(remembered) == .headsetOff(last: newer))
        #expect(HeadsetState.ok(newer).remembering(remembered) == .ok(newer))
    }
}
