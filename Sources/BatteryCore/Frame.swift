import Foundation

/// The two things the app ever asks the headset. There is deliberately no
/// way to make a query frame for any other command ID: these two cases are
/// the only input `Frame.query` accepts.
public enum Command: UInt8, CaseIterable, Sendable {
    /// Battery level, 0 to 100.
    case battery = 0x21
    /// Charging state, 0 on battery, non-zero while charging.
    case charging = 0x2A
}

/// One 64-byte output report for the vendor collection (report ID 2).
///
/// This is the only type that carries bytes to the device, and its
/// initializer is private, so the four values below are all that can ever be
/// sent: remote mode on, remote mode off, the battery query and the charging
/// query, byte for byte as in the README's Protocol table. Do not add a
/// public initializer or a frame for any other command. The OpenRazer driver
/// defines setters (EQ, sidetone, idle timer); none of them belong here.
public struct Frame: Hashable, Sendable {
    /// Output reports are 64 bytes including the report ID.
    public static let length = 64

    /// All 64 bytes, starting with the report ID `0x02`.
    public let bytes: [UInt8]

    /// The report ID, which is also byte 0.
    public var reportID: UInt8 { bytes[0] }

    /// Builds a frame from its leading bytes and pads it with zeros.
    private init(_ prefix: [UInt8]) {
        precondition(prefix.count <= Self.length)
        bytes = prefix + [UInt8](repeating: 0, count: Self.length - prefix.count)
    }

    /// "Remote mode on". Sent once to wake the radio link and again before
    /// each query, the way Synapse does it.
    public static let remoteOn = Frame([0x02, 0x80, 0x07, 0x00, 0x00, 0x50, 0x41, 0x0E, 0x00, 0x02, 0xE1, 0x01])

    /// "Remote mode off". Sent once after every query, success or not.
    public static let remoteOff = Frame([0x02, 0x80, 0x07, 0x00, 0x00, 0x50, 0x41, 0x0E, 0x00, 0x02, 0xE1, 0x00])

    private static let batteryQuery = Frame([0x02, 0x80, 0x08, 0x00, 0x00, 0x50, 0x41, 0x08, 0x00, 0x03, Command.battery.rawValue, 0x00])
    private static let chargingQuery = Frame([0x02, 0x80, 0x08, 0x00, 0x00, 0x50, 0x41, 0x08, 0x00, 0x03, Command.charging.rawValue, 0x00])

    /// The query frame for one of the two commands.
    public static func query(_ command: Command) -> Frame {
        switch command {
        case .battery: return batteryQuery
        case .charging: return chargingQuery
        }
    }

    /// Every frame the app may send. Tests check that nothing else is ever sent.
    public static let all: [Frame] = [remoteOn, remoteOff, batteryQuery, chargingQuery]
}
