import Foundation
import Testing
@testable import BatteryCore

@Suite("Status text")
struct StatusTextTests {
    let gmt = TimeZone(identifier: "GMT")!
    let britishEnglish = Locale(identifier: "en_GB")
    /// 2026-10-26 14:05 GMT.
    let at = Date(timeIntervalSince1970: 1_793_023_500)

    func reading(_ level: Int, _ charging: Bool?) -> Reading {
        Reading(level: level, charging: charging, at: at)!
    }

    @Test func statusLineMatchesScript() {
        #expect(StatusText.statusLine(reading(74, false)) == "battery: 74% (on battery)")
        #expect(StatusText.statusLine(reading(74, true)) == "battery: 74% (charging)")
        #expect(StatusText.statusLine(reading(74, nil)) == "battery: 74% (unknown)")
    }

    @Test func commandLineErrors() {
        #expect(StatusText.commandLineError(.noDongle) == "BlackShark V2 Pro 2.4 dongle (vendor page 0xFF00) not found")
        #expect(StatusText.commandLineError(.noReply) == "no battery reply (headset off or out of range?)")
        #expect(StatusText.commandLineError(.badReply(200)) == "unexpected battery value: 200")
        #expect(StatusText.commandLineError(.openFailed(.busy)) == "could not open dongle: busy (0xe00002c5)")
        #expect(StatusText.commandLineError(.openFailed(.notPermitted)) == "could not open dongle: not permitted (0xe00002e2)")
        #expect(StatusText.commandLineError(.reading(reading(74, false))) == nil)
    }

    @Test func openFailureCodes() {
        #expect(OpenFailure(code: Int32(bitPattern: 0xE000_02E2)) == .notPermitted)
        #expect(OpenFailure(code: Int32(bitPattern: 0xE000_02C5)) == .busy)
        #expect(OpenFailure(code: 5) == .other(5))
        #expect(OpenFailure.other(5).code == 5)
    }

    @Test func menuBarItemForEveryState() {
        let ok = HeadsetState.ok(reading(74, false))
        let charging = HeadsetState.ok(reading(74, true))
        let unknown = HeadsetState.ok(reading(74, nil))
        let off = HeadsetState.headsetOff(last: nil)
        let problem = HeadsetState.problem("Dongle busy, another app has it open", last: nil)

        #expect(StatusText.symbolName(.starting) == "headphones")
        #expect(StatusText.symbolName(.noDongle) == "headphones.slash")
        for state in [ok, charging, unknown, off, problem] {
            #expect(StatusText.symbolName(state) == "headphones")
        }

        #expect(StatusText.title(.starting) == "")
        #expect(StatusText.title(ok) == "74%")
        #expect(StatusText.title(charging) == "74%")
        #expect(StatusText.title(off) == "")
        #expect(StatusText.title(.noDongle) == "")
        #expect(StatusText.title(problem) == "!")

        #expect(StatusText.showsBolt(charging))
        #expect(!StatusText.showsBolt(ok))
        #expect(!StatusText.showsBolt(unknown))

        #expect(StatusText.appearsDisabled(off))
        #expect(StatusText.appearsDisabled(.noDongle))
        #expect(!StatusText.appearsDisabled(.starting))
        #expect(!StatusText.appearsDisabled(ok))
        #expect(!StatusText.appearsDisabled(problem))

        #expect(StatusText.toolTip(.starting) == "BlackShark battery: reading...")
        #expect(StatusText.toolTip(ok) == "BlackShark battery: 74%, on battery")
        #expect(StatusText.toolTip(charging) == "BlackShark battery: 74%, charging")
        #expect(StatusText.toolTip(unknown) == "BlackShark battery: 74%")
        #expect(StatusText.toolTip(off) == "Headset off or out of range")
        #expect(StatusText.toolTip(.noDongle) == "Dongle not connected")
        #expect(StatusText.toolTip(problem) == "Dongle busy, another app has it open")
    }

    @Test func menuHeadline() {
        #expect(StatusText.headline(.ok(reading(74, false))) == "Battery 74%, on battery")
        #expect(StatusText.headline(.ok(reading(74, true))) == "Charging, 74%")
        #expect(StatusText.headline(.ok(reading(74, nil))) == "Battery 74%")
        #expect(StatusText.headline(.headsetOff(last: nil)) == "Headset off or out of range")
        #expect(StatusText.headline(.noDongle) == "Dongle not connected")
        #expect(StatusText.headline(.problem("x", last: nil)) == "x")
        #expect(StatusText.headline(.starting) == "Reading...")
        #expect(
            StatusText.headline(HeadsetState.starting.applying(.openFailed(.notPermitted)))
                == "Not allowed to open the dongle (Privacy & Security, Input Monitoring)")
    }

    @Test func menuDetail() {
        let later = at.addingTimeInterval(600)
        func detail(_ state: HeadsetState, inFlight: Bool = false, now: Date) -> String? {
            StatusText.detail(state, inFlight: inFlight, now: now, locale: britishEnglish, timeZone: gmt)
        }
        #expect(detail(.ok(reading(74, false)), now: later) == "Updated 14:05")
        #expect(detail(.headsetOff(last: reading(74, false)), now: later) == "Last reading 74% at 14:05")
        #expect(detail(.problem("x", last: reading(74, false)), now: later) == "Last reading 74% at 14:05")
        #expect(detail(.headsetOff(last: nil), now: later) == nil)
        #expect(detail(.noDongle, now: later) == nil)
        #expect(detail(.starting, inFlight: true, now: later) == nil)
        #expect(detail(.ok(reading(74, false)), inFlight: true, now: later) == "Reading...")

        // A reading from another day carries its date.
        let nextDay = at.addingTimeInterval(86_400)
        let lastSeen = detail(.headsetOff(last: reading(74, false)), now: nextDay)
        #expect(lastSeen?.hasPrefix("Last reading 74% at 26/10/2026") == true)
        #expect(lastSeen?.hasSuffix("14:05") == true)
    }

    @Test func deviceLine() {
        let info = DongleInfo(
            identity: "location-0x20310000",
            locationID: 0x2031_0000,
            primaryUsagePage: 0x0C,
            usagePairs: [.init(page: 0x0C, usage: 1), .razerVendor]
        )
        #expect(
            StatusText.deviceLine(info, listenAccess: "granted")
                == "found location=0x20310000 primaryPage=0x0c pairs=[0x0c/0x01,0xff00/0x01] requiresTCC=no listenAccess=granted")
        #expect(info.hasVendorChannel)
    }

    @Test func readingRejectsLevelAbove100() {
        #expect(Reading(level: 101, charging: nil, at: at) == nil)
        #expect(Reading(level: -1, charging: nil, at: at) == nil)
        #expect(Reading(level: 100, charging: nil, at: at) != nil)
        #expect(Reading(level: 0, charging: nil, at: at) != nil)
    }
}
