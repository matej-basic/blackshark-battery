import Foundation

/// Every string the user sees: the menu bar item, the menu lines and the
/// `--status` output. Kept here so the wording is tested.
public enum StatusText {
    // MARK: Command line

    /// The `--status` line on success, the same as the Python script prints:
    /// `battery: 74% (on battery)`, `(charging)` or `(unknown)`.
    public static func statusLine(_ reading: Reading) -> String {
        let state: String
        switch reading.charging {
        case nil: state = "unknown"
        case true?: state = "charging"
        case false?: state = "on battery"
        }
        return "battery: \(reading.level)% (\(state))"
    }

    /// Printed on stderr when no dongle is found. Same text as the script.
    public static let dongleNotFound = "BlackShark V2 Pro 2.4 dongle (vendor page 0xFF00) not found"
    /// Printed on stderr when the battery query got no reply. Same text as the script.
    public static let noBatteryReply = "no battery reply (headset off or out of range?)"

    /// The stderr line for `--status` when the read did not give a reading.
    public static func commandLineError(_ outcome: ReadOutcome) -> String? {
        switch outcome {
        case .reading:
            return nil
        case .noReply:
            return noBatteryReply
        case .noDongle:
            return dongleNotFound
        case .badReply(let value):
            return "unexpected battery value: \(value)"
        case .openFailed(let failure):
            let reason: String
            switch failure {
            case .notPermitted: reason = "not permitted"
            case .busy: reason = "busy"
            case .other: reason = "error"
            }
            return "could not open dongle: \(reason) (\(hexCode(failure.code)))"
        }
    }

    /// The `--device` line, for example
    /// `found location=0x20310000 primaryPage=0x0c pairs=[0x0c/0x01,0xff00/0x01] requiresTCC=no listenAccess=granted`.
    public static func deviceLine(_ info: DongleInfo, listenAccess: String) -> String {
        let location = info.locationID.map { String(format: "0x%08x", $0) } ?? "nil"
        let primary = info.primaryUsagePage.map { String(format: "0x%02x", $0) } ?? "nil"
        let pairs = info.usagePairs.map { String(format: "0x%02x/0x%02x", $0.page, $0.usage) }.joined(separator: ",")
        let tcc = info.requiresTCC == true ? "yes" : "no"
        return "found location=\(location) primaryPage=\(primary) pairs=[\(pairs)] requiresTCC=\(tcc) listenAccess=\(listenAccess)"
    }

    /// An IOReturn code as `0xe00002e2`.
    public static func hexCode(_ code: Int32) -> String {
        String(format: "0x%08x", UInt32(bitPattern: code))
    }

    // MARK: Problems

    public static func openFailed(_ failure: OpenFailure) -> String {
        switch failure {
        case .notPermitted:
            return "Not allowed to open the dongle (Privacy & Security, Input Monitoring)"
        case .busy:
            return "Dongle busy, another app has it open"
        case .other(let code):
            return "Could not open the dongle (\(hexCode(code)))"
        }
    }

    public static func badReply(_ value: Int) -> String {
        "Unexpected battery value: \(value)"
    }

    // MARK: Menu bar item

    public static let headsetOff = "Headset off or out of range"
    public static let dongleNotConnected = "Dongle not connected"
    public static let reading = "Reading..."
    /// Shown instead of the icon if the SF Symbol is missing, so the item never vanishes.
    public static let fallbackTitle = "BS"

    /// The SF Symbol for the menu bar item.
    public static func symbolName(_ state: HeadsetState) -> String {
        if case .noDongle = state {
            return "headphones.slash"
        }
        return "headphones"
    }

    /// The text next to the icon: the level, `!` for a problem, else nothing.
    public static func title(_ state: HeadsetState) -> String {
        switch state {
        case .ok(let reading): return "\(reading.level)%"
        case .problem: return "!"
        case .starting, .noDongle, .headsetOff: return ""
        }
    }

    /// True when the title is followed by a bolt (charging).
    public static func showsBolt(_ state: HeadsetState) -> Bool {
        if case .ok(let reading) = state {
            return reading.charging == true
        }
        return false
    }

    /// Greyed-out icon when there is nothing current to show.
    public static func appearsDisabled(_ state: HeadsetState) -> Bool {
        switch state {
        case .noDongle, .headsetOff: return true
        case .starting, .ok, .problem: return false
        }
    }

    public static func toolTip(_ state: HeadsetState) -> String {
        switch state {
        case .starting:
            return "BlackShark battery: reading..."
        case .ok(let reading):
            switch reading.charging {
            case nil: return "BlackShark battery: \(reading.level)%"
            case true?: return "BlackShark battery: \(reading.level)%, charging"
            case false?: return "BlackShark battery: \(reading.level)%, on battery"
            }
        case .headsetOff:
            return headsetOff
        case .noDongle:
            return dongleNotConnected
        case .problem(let text, _):
            return text
        }
    }

    // MARK: Menu

    /// The first menu line.
    public static func headline(_ state: HeadsetState) -> String {
        switch state {
        case .starting:
            return reading
        case .ok(let reading):
            switch reading.charging {
            case nil: return "Battery \(reading.level)%"
            case true?: return "Charging, \(reading.level)%"
            case false?: return "Battery \(reading.level)%, on battery"
            }
        case .headsetOff:
            return headsetOff
        case .noDongle:
            return dongleNotConnected
        case .problem(let text, _):
            return text
        }
    }

    /// The second menu line: "Reading..." while a read runs, when the shown
    /// level was read, or when the last good one was. Nil hides the line.
    public static func detail(_ state: HeadsetState, inFlight: Bool, now: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String? {
        if case .starting = state {
            return nil
        }
        if inFlight {
            return reading
        }
        switch state {
        case .ok(let reading):
            return "Updated \(time(reading.at, now: now, locale: locale, timeZone: timeZone))"
        case .headsetOff(let last?), .problem(_, let last?):
            return "Last reading \(last.level)% at \(time(last.at, now: now, locale: locale, timeZone: timeZone))"
        default:
            return nil
        }
    }

    /// A short time, with the date in front when it is not today.
    public static func time(_ date: Date, now: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = calendar.isDate(date, inSameDayAs: now) ? .none : .short
        return formatter.string(from: date)
    }
}
