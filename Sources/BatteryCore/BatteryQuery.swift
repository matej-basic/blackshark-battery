import Foundation

/// The connection to the dongle that a query needs. The app's IOKit class
/// `HIDTransport` conforms to it; tests use a fake.
///
/// `send` takes a `Frame`, never raw bytes, so a query can only ever send
/// one of the four frames in `Frame.all`.
public protocol HIDLink: AnyObject {
    /// Sends one output report. Returns false if the system reported an error.
    func send(_ frame: Frame) -> Bool
    /// The next input report, or nil if none arrived within `timeout`.
    /// Same meaning as `dev.read(LEN, ms)` in hidapi.
    func read(timeout: TimeInterval) -> [UInt8]?
    func sleep(_ seconds: TimeInterval)
    /// Monotonic seconds, for the reply window.
    func now() -> TimeInterval
    /// Where `-v` frame logging goes, or nil when it is off.
    var log: ((String) -> Void)? { get }
}

/// The waits in a query, in seconds. The defaults are the Python script's.
public struct QueryTiming: Equatable, Sendable {
    /// Pause after each "remote mode" frame.
    public var gap: TimeInterval
    /// How many times the query is sent before giving up.
    public var attempts: Int
    /// How long to wait for a reply after each query.
    public var replyWindow: TimeInterval
    /// Timeout of one read inside the reply window.
    public var readSlice: TimeInterval
    /// Timeout of one read while draining leftover reports.
    public var drainSlice: TimeInterval

    public init(
        gap: TimeInterval = 0.035,
        attempts: Int = 3,
        replyWindow: TimeInterval = 0.3,
        readSlice: TimeInterval = 0.05,
        drainSlice: TimeInterval = 0.005
    ) {
        self.gap = gap
        self.attempts = attempts
        self.replyWindow = replyWindow
        self.readSlice = readSlice
        self.drainSlice = drainSlice
    }
}

/// The query sequence, a line-by-line port of `query()` in
/// blackshark_battery.py:
///
/// - drain leftover input reports,
/// - one sacrificial "remote on" to wake the radio link,
/// - up to `attempts` times: "remote on", the query, then read until the
///   reply window has passed, stopping at the first reply that parses,
/// - always "remote off" at the end.
///
/// A successful read of both queries is 8 frames and about 0.3 s.
public enum BatteryQuery {
    /// Runs one query and returns the reply payload, or nil if no reply came.
    public static func run(_ command: Command, on link: HIDLink, timing: QueryTiming = QueryTiming()) -> [UInt8]? {
        while let data = link.read(timeout: timing.drainSlice), !data.isEmpty {}  // drain
        _ = link.send(.remoteOn)  // sacrificial wake-up frame
        link.sleep(timing.gap)
        var result: [UInt8]?
        for _ in 0..<timing.attempts {
            // As in the script, a failed write does not stop the sequence;
            // the query then simply gets no reply.
            _ = link.send(.remoteOn)
            link.sleep(timing.gap)
            _ = link.send(.query(command))
            let end = link.now() + timing.replyWindow
            while link.now() < end {
                guard let data = link.read(timeout: timing.readSlice), !data.isEmpty else { continue }
                let tag = ReplyParser.isStatusFrame(data) ? " (status)" : ""
                link.log?("RX: \(hex(data.prefix(24))) ...\(tag)")
                if let parsed = ReplyParser.parse(data, command: command) {
                    result = parsed
                    break
                }
            }
            if result != nil {
                break
            }
        }
        _ = link.send(.remoteOff)
        link.sleep(timing.gap)
        return result
    }
}

/// Reads level and charging state, the port of `main()` in the script: the
/// battery query first; without a battery reply the charging query is not
/// sent at all.
public func readHeadset(on link: HIDLink, timing: QueryTiming = QueryTiming(), at date: Date = Date()) -> ReadOutcome {
    guard let battery = BatteryQuery.run(.battery, on: link, timing: timing), let level = battery.first else {
        return .noReply
    }
    let charging = BatteryQuery.run(.charging, on: link, timing: timing).map { $0[0] != 0 }
    guard let reading = Reading(level: Int(level), charging: charging, at: date) else {
        return .badReply(Int(level))
    }
    return .reading(reading)
}
