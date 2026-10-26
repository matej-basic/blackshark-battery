import Foundation
import Testing
@testable import BatteryCore

/// A dongle without hardware. It records every frame sent, answers each
/// query frame with the next scripted batch of input reports, and keeps a
/// fake clock that `read` and `sleep` advance.
final class FakeLink: HIDLink {
    /// Reports waiting to be read, oldest first.
    var queue: [[UInt8]]
    /// For each command, one batch of reports per query sent. A missing or
    /// empty batch means no reply to that attempt.
    var script: [Command: [[[UInt8]]]]
    var sendResult = true
    private(set) var sent: [Frame] = []
    /// Fake clock time at which each query frame was sent.
    private(set) var queryTimes: [TimeInterval] = []
    private(set) var logLines: [String] = []
    private var clock: TimeInterval = 0

    init(leftover: [[UInt8]] = [], script: [Command: [[[UInt8]]]] = [:]) {
        queue = leftover
        self.script = script
    }

    var log: ((String) -> Void)? {
        { [weak self] line in self?.logLines.append(line) }
    }

    func send(_ frame: Frame) -> Bool {
        sent.append(frame)
        for command in Command.allCases where frame == .query(command) {
            queryTimes.append(clock)
            if var batches = script[command], !batches.isEmpty {
                queue += batches.removeFirst()
                script[command] = batches
            }
        }
        return sendResult
    }

    func read(timeout: TimeInterval) -> [UInt8]? {
        if !queue.isEmpty {
            clock += 0.001
            return queue.removeFirst()
        }
        clock += timeout
        return nil
    }

    func sleep(_ seconds: TimeInterval) {
        clock += seconds
    }

    func now() -> TimeInterval {
        clock
    }
}

@Suite("Query sequence")
struct BatteryQueryTests {
    let on = Frame.remoteOn
    let off = Frame.remoteOff
    let battery = Frame.query(.battery)
    let charging = Frame.query(.charging)

    /// The safety check applied to every scenario: nothing outside `Frame.all` was sent.
    func expectOnlyAllowedFrames(_ link: FakeLink) {
        for frame in link.sent {
            #expect(Frame.all.contains(frame))
        }
    }

    @Test func success() {
        let link = FakeLink(script: [.battery: [[Fixture.batteryReply]]])
        #expect(BatteryQuery.run(.battery, on: link) == [0x4a])
        #expect(link.sent == [on, on, battery, off])
        expectOnlyAllowedFrames(link)
    }

    @Test func statusFramesBeforeReply() {
        let link = FakeLink(script: [.battery: [[Fixture.status1, Fixture.status2, Fixture.batteryReply]]])
        #expect(BatteryQuery.run(.battery, on: link) == [0x4a])
        #expect(link.sent == [on, on, battery, off])
        #expect(link.logLines.filter { $0.hasPrefix("RX: ") }.count == 3)
        #expect(link.logLines[0].hasSuffix("(status)"))
        expectOnlyAllowedFrames(link)
    }

    @Test func noReply() {
        let link = FakeLink()
        #expect(BatteryQuery.run(.battery, on: link) == nil)
        #expect(link.sent == [on, on, battery, on, battery, on, battery, off])
        // Between two queries: the 0.3 s reply window, then "remote on" and its 35 ms gap.
        #expect(link.queryTimes.count == 3)
        for (earlier, later) in zip(link.queryTimes, link.queryTimes.dropFirst()) {
            let waited = later - earlier - 0.035
            #expect(waited >= 0.3 && waited < 0.36)
        }
        expectOnlyAllowedFrames(link)
    }

    @Test func replyOnSecondAttempt() {
        let link = FakeLink(script: [.battery: [[], [Fixture.batteryReply]]])
        #expect(BatteryQuery.run(.battery, on: link) == [0x4a])
        #expect(link.sent == [on, on, battery, on, battery, off])
        expectOnlyAllowedFrames(link)
    }

    @Test func leftoverReportsAreDrained() {
        let old = Fixture.batteryReply(level: 0x10)
        let link = FakeLink(leftover: [old, Fixture.status1], script: [.battery: [[Fixture.batteryReply]]])
        #expect(BatteryQuery.run(.battery, on: link) == [0x4a])
        #expect(link.sent == [on, on, battery, off])
        // Drained reports are not parsed or logged.
        #expect(link.logLines.count == 1)
        expectOnlyAllowedFrames(link)
    }

    @Test func failedSendDoesNotStopTheSequence() {
        let link = FakeLink(script: [.battery: [[Fixture.batteryReply]]])
        link.sendResult = false
        #expect(BatteryQuery.run(.battery, on: link) == [0x4a])
        #expect(link.sent == [on, on, battery, off])

        let silent = FakeLink()
        silent.sendResult = false
        #expect(BatteryQuery.run(.battery, on: silent) == nil)
        #expect(silent.sent == [on, on, battery, on, battery, on, battery, off])
        expectOnlyAllowedFrames(link)
        expectOnlyAllowedFrames(silent)
    }

    @Test func readHeadsetOnBattery() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let link = FakeLink(script: [.battery: [[Fixture.batteryReply]], .charging: [[Fixture.chargingReply]]])
        let outcome = readHeadset(on: link, at: date)
        #expect(outcome == .reading(Reading(level: 74, charging: false, at: date)!))
        #expect(link.sent == [on, on, battery, off, on, on, charging, off])
        expectOnlyAllowedFrames(link)
    }

    @Test func readHeadsetCharging() {
        let link = FakeLink(script: [.battery: [[Fixture.batteryReply]], .charging: [[Fixture.chargingReply(value: 1)]]])
        guard case .reading(let reading) = readHeadset(on: link) else {
            Issue.record("expected a reading")
            return
        }
        #expect(reading.level == 74)
        #expect(reading.charging == true)
        expectOnlyAllowedFrames(link)
    }

    @Test func readHeadsetChargingUnknown() {
        let link = FakeLink(script: [.battery: [[Fixture.batteryReply]]])
        guard case .reading(let reading) = readHeadset(on: link) else {
            Issue.record("expected a reading")
            return
        }
        #expect(reading.level == 74)
        #expect(reading.charging == nil)
        expectOnlyAllowedFrames(link)
    }

    @Test func readHeadsetNoBatteryReplySkipsCharging() {
        let link = FakeLink(script: [.charging: [[Fixture.chargingReply]]])
        #expect(readHeadset(on: link) == .noReply)
        #expect(!link.sent.contains(charging))
        #expect(link.sent.count == 8)
        expectOnlyAllowedFrames(link)
    }

    @Test func readHeadsetLevelAbove100IsBadReply() {
        let link = FakeLink(script: [.battery: [[Fixture.batteryReply(level: 200)]], .charging: [[Fixture.chargingReply]]])
        #expect(readHeadset(on: link) == .badReply(200))
        expectOnlyAllowedFrames(link)
    }
}
