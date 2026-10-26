import Foundation

/// What asks for a poll.
public enum PollTrigger: Sendable {
    /// The first time the dongle is seen after the app started.
    case launch
    case dongleArrived
    /// The one-shot timer set after the previous read.
    case timer
    case menuOpened
    /// The "Refresh now" menu item.
    case refreshNow
    case didWake
}

/// When to read the headset, written as a pure function so it can be tested
/// without a dongle.
///
/// - No dongle, or a read already running: never poll. The running read
///   updates the menu when it finishes.
/// - Launch and dongle arrival: poll after `arrivalDelay`, because a freshly
///   enumerated dongle and the radio link need a moment.
/// - Wake from sleep: poll after `wakeDelay`. USB devices re-enumerate after
///   wake, and the arrival that may follow is absorbed by the rules above.
/// - Menu opened: poll at once if the last attempt is older than
///   `menuOpenMinAge`, otherwise not at all.
/// - Refresh now and the timer: poll at once.
/// - After every read the next timer is `chargingInterval` while charging
///   and `interval` otherwise.
/// - After a read that failed for a reason that usually clears up quickly
///   (the dongle was busy or could not be opened, or no device object could
///   be made although the dongle is present), the next timer is
///   `retryInterval`, for up to `maxQuickRetries` failures in a row. After
///   that it falls back to the normal interval, so a dongle that stays busy
///   is not polled every few seconds. "Headset off" is not such a failure.
public struct PollPolicy: Equatable, Sendable {
    /// Seconds between reads on battery or with the headset off.
    public var interval: TimeInterval
    /// Seconds between reads while charging.
    public var chargingInterval: TimeInterval
    /// Opening the menu reads again only if the last attempt is older than this.
    public var menuOpenMinAge: TimeInterval
    public var arrivalDelay: TimeInterval
    public var wakeDelay: TimeInterval
    /// Seconds until the next read after a failure that may clear up quickly.
    public var retryInterval: TimeInterval
    /// How many such failures in a row get `retryInterval` before the
    /// normal interval takes over again.
    public var maxQuickRetries: Int

    /// The shortest interval the hidden `pollIntervalSeconds` setting can set.
    public static let minimumInterval: TimeInterval = 30

    public init(
        interval: TimeInterval = 300,
        chargingInterval: TimeInterval = 120,
        menuOpenMinAge: TimeInterval = 60,
        arrivalDelay: TimeInterval = 1.5,
        wakeDelay: TimeInterval = 5,
        retryInterval: TimeInterval = 20,
        maxQuickRetries: Int = 3
    ) {
        self.interval = interval
        self.chargingInterval = chargingInterval
        self.menuOpenMinAge = menuOpenMinAge
        self.arrivalDelay = arrivalDelay
        self.wakeDelay = wakeDelay
        self.retryInterval = retryInterval
        self.maxQuickRetries = maxQuickRetries
    }

    /// The default policy with `interval` replaced by an override, clamped
    /// to at least `minimumInterval`. Nil keeps the default.
    public static func withIntervalOverride(_ seconds: TimeInterval?) -> PollPolicy {
        var policy = PollPolicy()
        if let seconds {
            policy.interval = max(seconds, minimumInterval)
        }
        return policy
    }

    /// The result of `decide`.
    public struct Decision: Equatable, Sendable {
        /// Seconds to wait before polling; 0 means now, nil means do not poll.
        public var pollAfter: TimeInterval?

        public init(pollAfter: TimeInterval?) {
            self.pollAfter = pollAfter
        }
    }

    /// Works out whether and when to poll after `trigger`.
    public func decide(_ trigger: PollTrigger, dongle: Bool, inFlight: Bool, lastAttempt: Date?, now: Date) -> Decision {
        guard dongle, !inFlight else {
            return Decision(pollAfter: nil)
        }
        switch trigger {
        case .launch, .dongleArrived:
            return Decision(pollAfter: arrivalDelay)
        case .didWake:
            return Decision(pollAfter: wakeDelay)
        case .menuOpened:
            if let lastAttempt, now.timeIntervalSince(lastAttempt) < menuOpenMinAge {
                return Decision(pollAfter: nil)
            }
            return Decision(pollAfter: 0)
        case .refreshNow, .timer:
            return Decision(pollAfter: 0)
        }
    }

    /// True for read failures worth retrying soon: the dongle was busy or
    /// could not be opened, or the read found no dongle although the monitor
    /// still reports one. Not permitted, a bad reply and "headset off" are not.
    public func isRetryable(_ outcome: ReadOutcome, donglePresent: Bool) -> Bool {
        switch outcome {
        case .openFailed(.busy), .openFailed(.other):
            return true
        case .noDongle:
            return donglePresent
        case .openFailed(.notPermitted), .reading, .noReply, .badReply:
            return false
        }
    }

    /// The count of retryable failures in a row after `outcome`: one more
    /// than `previous` for a retryable failure, otherwise 0.
    public func consecutiveFailures(after outcome: ReadOutcome, donglePresent: Bool, previous: Int) -> Int {
        isRetryable(outcome, donglePresent: donglePresent) ? previous + 1 : 0
    }

    /// Seconds until the next timer poll after a read. `failures` is the
    /// count from `consecutiveFailures`, including this read.
    public func nextTimer(after outcome: ReadOutcome, state: HeadsetState, donglePresent: Bool, failures: Int) -> TimeInterval {
        if isRetryable(outcome, donglePresent: donglePresent) && failures <= maxQuickRetries {
            return retryInterval
        }
        return nextTimer(after: state)
    }

    /// Seconds until the next timer poll, given the state after a read.
    public func nextTimer(after state: HeadsetState) -> TimeInterval {
        if case .ok(let reading) = state, reading.charging == true {
            return chargingInterval
        }
        return interval
    }
}
