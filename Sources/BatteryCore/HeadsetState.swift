import Foundation

/// One good battery reading.
public struct Reading: Equatable, Codable, Sendable {
    /// Battery level in percent, 0 to 100.
    public var level: Int
    /// True while charging, false on battery, nil when the charging query
    /// got no reply.
    public var charging: Bool?
    /// When the reading was taken.
    public var at: Date

    /// Returns nil for a level outside 0...100. The Python script would
    /// print such a value as it is; the app reports it as a bad reply.
    public init?(level: Int, charging: Bool?, at: Date) {
        guard (0...100).contains(level) else { return nil }
        self.level = level
        self.charging = charging
        self.at = at
    }
}

/// Why the dongle could not be opened.
public enum OpenFailure: Equatable, Sendable {
    /// `kIOReturnNotPermitted`: Input Monitoring denied. Not expected for
    /// this dongle, which has no `RequiresTCCAuthorization` property.
    case notPermitted
    /// `kIOReturnExclusiveAccess`: something holds the dongle seized, for
    /// example the Python script mid-run, or Synapse.
    case busy
    /// Any other IOReturn code.
    case other(Int32)

    /// `kIOReturnNotPermitted`, written out so the core needs no IOKit.
    public static let notPermittedCode = Int32(bitPattern: 0xE000_02E2)
    /// `kIOReturnExclusiveAccess`.
    public static let busyCode = Int32(bitPattern: 0xE000_02C5)

    /// Maps the result of opening the device to a failure.
    public init(code: Int32) {
        switch code {
        case Self.notPermittedCode: self = .notPermitted
        case Self.busyCode: self = .busy
        default: self = .other(code)
        }
    }

    /// The IOReturn code this failure stands for.
    public var code: Int32 {
        switch self {
        case .notPermitted: return Self.notPermittedCode
        case .busy: return Self.busyCode
        case .other(let code): return code
        }
    }
}

/// What one read of the headset produced.
public enum ReadOutcome: Equatable, Sendable {
    case reading(Reading)
    /// The dongle answered nothing to the battery query: headset off or out of range.
    case noReply
    /// The battery reply carried a value above 100.
    case badReply(Int)
    case noDongle
    case openFailed(OpenFailure)
}

/// What the menu bar shows.
public enum HeadsetState: Equatable, Sendable {
    /// Dongle seen or not yet known, no read finished.
    case starting
    case noDongle
    /// Dongle present, no reply.
    case headsetOff(last: Reading?)
    case ok(Reading)
    /// Open failed or bad reply. The string is the text for the menu.
    case problem(String, last: Reading?)

    /// The last good reading this state knows about.
    public var lastReading: Reading? {
        switch self {
        case .starting, .noDongle: return nil
        case .headsetOff(let last), .problem(_, let last): return last
        case .ok(let reading): return reading
        }
    }

    /// The state after a read. The last good reading is kept through
    /// "headset off" and problems, so the menu can say when the level was
    /// last seen.
    public func applying(_ outcome: ReadOutcome) -> HeadsetState {
        switch outcome {
        case .reading(let reading):
            return .ok(reading)
        case .noReply:
            return .headsetOff(last: lastReading)
        case .badReply(let value):
            return .problem(StatusText.badReply(value), last: lastReading)
        case .noDongle:
            return .noDongle
        case .openFailed(let failure):
            return .problem(StatusText.openFailed(failure), last: lastReading)
        }
    }

    /// Fills in `remembered` (the reading stored in the settings) as the last
    /// reading when this state has none, for example after a relaunch or a
    /// replug with the headset off.
    public func remembering(_ remembered: Reading?) -> HeadsetState {
        switch self {
        case .headsetOff(last: .none):
            return .headsetOff(last: remembered)
        case .problem(let text, last: .none):
            return .problem(text, last: remembered)
        default:
            return self
        }
    }
}
