import AppKit
import BatteryCore
import Foundation
import IOKit.hid

// Command line hooks, handy for testing without clicking the menu:
//   --status            reads the headset once and prints "battery: 74% (on battery)"
//   --listen SECONDS    sends nothing, prints every input report for that long
//   --device            prints what the app knows about the dongle, without opening it
//   -v                  anywhere: log every frame in hex on stderr (also for the menu bar app)
let args = Array(CommandLine.arguments.dropFirst())
// -v is a modifier, not a command, so it is taken out before the switch.
let verbose = args.contains("-v")
let commands = args.filter { $0 != "-v" }

/// Frame logging for -v, in the Python script's format, on stderr.
let frameLog: ((String) -> Void)? =
    verbose
    ? { line in FileHandle.standardError.write(Data("\(line)\n".utf8)) }
    : nil

func printError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}

/// Watches for the dongle for 0.5 seconds, the way the menu bar app does.
func findDongle() -> DongleMonitor {
    let monitor = DongleMonitor()
    monitor.start()
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    return monitor
}

/// Reads the headset once and prints the result like the Python script.
func printStatus() -> Int32 {
    let monitor = findDongle()
    guard let service = monitor.service else {
        printError(StatusText.dongleNotFound)
        return 1
    }
    // The read runs on the reader's io queue and its callbacks on the HID
    // callback queue, so waiting here on the main thread cannot deadlock.
    var outcome = ReadOutcome.noDongle
    let done = DispatchSemaphore(value: 0)
    HeadsetReader(log: frameLog).read(service: service) { result in
        outcome = result
        done.signal()
    }
    done.wait()
    if case .reading(let reading) = outcome {
        print(StatusText.statusLine(reading))
        return 0
    }
    printError(StatusText.commandLineError(outcome) ?? "unexpected outcome")
    return 1
}

/// Prints every input report for `seconds`, sending nothing.
func listen(_ seconds: TimeInterval) -> Int32 {
    let monitor = findDongle()
    guard let service = monitor.service else {
        printError(StatusText.dongleNotFound)
        return 1
    }
    var result: Result<Int, HeadsetReader.OpenError> = .failure(.noDongle)
    let done = DispatchSemaphore(value: 0)
    HeadsetReader(log: frameLog).listen(service: service, seconds: seconds) { report in
        print("unsolicited RX: \(hex(report))")
    } completion: {
        result = $0
        done.signal()
    }
    done.wait()
    switch result {
    case .success(let count):
        print(String(format: "listen %.0fs: %d input reports", seconds, count))
        return 0
    case .failure(.noDongle):
        printError(StatusText.dongleNotFound)
        return 1
    case .failure(.openFailed(let failure)):
        printError(StatusText.commandLineError(.openFailed(failure)) ?? "could not open dongle")
        return 1
    }
}

/// Prints one line about the dongle. Opens nothing and sends nothing.
func describeDongle() -> Int32 {
    let monitor = findDongle()
    guard let info = monitor.devices.first else {
        print("not found")
        return 1
    }
    // IOHIDCheckAccess only reads the permission state; it never shows a prompt.
    let access: String
    switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
    case kIOHIDAccessTypeGranted: access = "granted"
    case kIOHIDAccessTypeDenied: access = "denied"
    default: access = "unknown"
    }
    print(StatusText.deviceLine(info, listenAccess: access))
    return 0
}

if let first = commands.first {
    var status: Int32 = 0
    switch first {
    case "--status":
        status = printStatus()
    case "--listen":
        guard commands.count > 1, let seconds = Double(commands[1]), seconds > 0 else {
            printError("usage: --listen SECONDS")
            exit(2)
        }
        status = listen(seconds)
    case "--device":
        status = describeDongle()
    default:
        printError("unknown argument: \(first)")
        exit(2)
    }
    exit(status)
}

// Normal start: run as a menu bar app with no Dock icon.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate(frameLog: frameLog)
app.delegate = delegate
app.run()
