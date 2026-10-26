import Testing
@testable import BatteryCore

@Suite("Reply parser")
struct ReplyParserTests {
    @Test func capturedReplies() {
        #expect(ReplyParser.parse(Fixture.batteryReply, command: .battery) == [0x4a])
        #expect(ReplyParser.parse(Fixture.chargingReply, command: .charging) == [0x00])
    }

    @Test func readmeExample() {
        #expect(ReplyParser.parse(Fixture.readmeBatteryReply, command: .battery) == [0x4b])
    }

    @Test func statusFramesAreNotReplies() {
        for frame in [Fixture.status1, Fixture.status2] {
            #expect(ReplyParser.parse(frame, command: .battery) == nil)
            #expect(ReplyParser.parse(frame, command: .charging) == nil)
            #expect(ReplyParser.isStatusFrame(frame))
        }
        #expect(!ReplyParser.isStatusFrame(Fixture.batteryReply))
    }

    @Test func echoMismatchIsRejected() {
        #expect(ReplyParser.parse(Fixture.batteryReply, command: .charging) == nil)
        #expect(ReplyParser.parse(Fixture.chargingReply, command: .battery) == nil)
    }

    @Test func nackIsRejected() {
        var data = Fixture.batteryReply
        data[13] = 0x00
        #expect(ReplyParser.parse(data, command: .battery) == nil)
    }

    @Test func replyWithoutReportIDUsesSecondLayout() {
        let data = Array(Fixture.batteryReply.dropFirst())
        #expect(ReplyParser.parse(data, command: .battery) == [0x4a])
    }

    @Test func lengthBoundary() {
        // With the report ID the payload starts at byte 15, so 15 bytes are too few.
        let prefix = Array(Fixture.readmeBatteryReply.prefix(15))
        #expect(ReplyParser.parse(prefix, command: .battery) == nil)
        #expect(ReplyParser.parse(Array(Fixture.readmeBatteryReply.prefix(16)), command: .battery) == [0x4b])
    }

    @Test func zeroPayloadLengthStillReturnsOneByte() {
        var data = Fixture.batteryReply
        data[14] = 0
        #expect(ReplyParser.parse(data, command: .battery) == [0x4a])
    }

    @Test func payloadLengthIsClampedToBuffer() {
        var data = Fixture.batteryReply
        data[14] = 200
        #expect(ReplyParser.parse(data, command: .battery) == Array(data[15...]))
        #expect(ReplyParser.parse(data, command: .battery)?.count == 49)
    }

    @Test func consumerReportAndEmptyInput() {
        #expect(ReplyParser.parse(Fixture.consumerReport, command: .battery) == nil)
        #expect(ReplyParser.parse([], command: .battery) == nil)
    }

    @Test func hexMatchesScript() {
        #expect(hex([0x02, 0x80, 0x0e, 0xff]) == "02 80 0e ff")
        #expect(hex([]) == "")
    }
}
