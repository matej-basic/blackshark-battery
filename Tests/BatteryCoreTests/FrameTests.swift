// Tests use the swift-testing library (`import Testing`), not XCTest:
// the Command Line Tools on macOS ship swift-testing but not XCTest, and
// swift-testing is also part of the Linux Swift toolchain.
import Testing
@testable import BatteryCore

// Input reports captured from the real dongle on 2026-10-26 with
// `blackshark_battery.py -v`. The script logs the first 24 bytes; the rest
// is padded with zeros up to 64.
enum Fixture {
    static func padded(_ prefix: [UInt8]) -> [UInt8] {
        prefix + [UInt8](repeating: 0, count: 64 - prefix.count)
    }

    /// Status frame the dongle sends before each reply.
    static let status1 = padded([
        0x02, 0x0d, 0x50, 0x49, 0x01, 0xc0, 0xb5, 0x91, 0x09, 0x00, 0x03, 0x00,
        0x0e, 0x80, 0x00, 0x50, 0x49, 0x01, 0xc0, 0xb3, 0x4f, 0x09, 0x00, 0x03,
    ])
    static let status2 = padded([
        0x02, 0x0d, 0x50, 0x49, 0x01, 0xc0, 0xd5, 0x91, 0x09, 0x00, 0x03, 0x00,
        0x0e, 0x80, 0x00, 0x50, 0x49, 0x01, 0xc0, 0xb3, 0x4f, 0x09, 0x00, 0x03,
    ])
    /// Battery reply, 0x4a = 74%.
    static let batteryReply = padded([
        0x02, 0x0e, 0x50, 0x49, 0x08, 0xdc, 0x77, 0x3c, 0x09, 0x00, 0x04, 0x00,
        0x21, 0x01, 0x01, 0x4a, 0x49, 0x01, 0xc0, 0xb3, 0x4f, 0x09, 0x00, 0x03,
    ])
    /// Charging reply, 0x00 = on battery.
    static let chargingReply = padded([
        0x02, 0x0e, 0x50, 0x49, 0x08, 0xdd, 0xe5, 0x3c, 0x09, 0x00, 0x04, 0x00,
        0x2a, 0x01, 0x01, 0x00, 0x49, 0x01, 0xc0, 0xb3, 0x4f, 0x09, 0x00, 0x03,
    ])
    /// The battery reply from the README, 0x4b = 75%.
    static let readmeBatteryReply: [UInt8] = [0x02, 0x0e, 0x50, 0x49, 0x08, 0xce, 0x2d, 0x83, 0x03, 0x00, 0x04, 0x00, 0x21, 0x01, 0x01, 0x4b]
    /// A consumer control report (report ID 1, volume keys).
    static let consumerReport: [UInt8] = [0x01, 0x00, 0x00]

    /// A battery reply with any level, for the bad-value tests.
    static func batteryReply(level: UInt8) -> [UInt8] {
        var data = batteryReply
        data[15] = level
        return data
    }

    /// A charging reply with any value.
    static func chargingReply(value: UInt8) -> [UInt8] {
        var data = chargingReply
        data[15] = value
        return data
    }
}

@Suite("Frames")
struct FrameTests {
    // Typed from the README's Protocol table: the first 12 bytes, then 52 zeros.
    static let zeros = [UInt8](repeating: 0, count: 52)
    static let remoteOn: [UInt8] = [0x02, 0x80, 0x07, 0x00, 0x00, 0x50, 0x41, 0x0e, 0x00, 0x02, 0xe1, 0x01] + zeros
    static let remoteOff: [UInt8] = [0x02, 0x80, 0x07, 0x00, 0x00, 0x50, 0x41, 0x0e, 0x00, 0x02, 0xe1, 0x00] + zeros
    static let batteryQuery: [UInt8] = [0x02, 0x80, 0x08, 0x00, 0x00, 0x50, 0x41, 0x08, 0x00, 0x03, 0x21, 0x00] + zeros
    static let chargingQuery: [UInt8] = [0x02, 0x80, 0x08, 0x00, 0x00, 0x50, 0x41, 0x08, 0x00, 0x03, 0x2a, 0x00] + zeros

    @Test func remoteOnBytes() {
        #expect(Frame.remoteOn.bytes == Self.remoteOn)
    }

    @Test func remoteOffBytes() {
        #expect(Frame.remoteOff.bytes == Self.remoteOff)
    }

    @Test func batteryQueryBytes() {
        #expect(Frame.query(.battery).bytes == Self.batteryQuery)
    }

    @Test func chargingQueryBytes() {
        #expect(Frame.query(.charging).bytes == Self.chargingQuery)
    }

    @Test func everyFrameIs64BytesWithReportID2() {
        for frame in Frame.all {
            #expect(frame.bytes.count == 64)
            #expect(frame.reportID == 2)
        }
    }

    @Test func allHoldsExactlyTheFourFrames() {
        #expect(Frame.all.count == 4)
        #expect(Set(Frame.all.map(\.bytes)).count == 4)
        #expect(Set(Frame.all.map(\.bytes)) == [Self.remoteOn, Self.remoteOff, Self.batteryQuery, Self.chargingQuery])
    }

    @Test func onlyTwoCommands() {
        #expect(Command.allCases.map(\.rawValue) == [0x21, 0x2A])
    }
}
