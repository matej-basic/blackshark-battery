import BatteryCore
import Foundation
import IOKit.hid

/// The one place that opens the dongle and sends it output reports.
///
/// Hardware safety: `send(_:)` takes a `Frame`, and `Frame` can only be one of
/// the four frames in `Frame.all` (remote mode on and off, the battery query
/// and the charging query). This file holds the only SetReport call in the
/// code base, always with an output report; `build.sh` checks that before it
/// builds. Do not add setters, feature reports or any other command here.
///
/// Why it works this way:
/// - The transport creates its own IOHIDDevice from the service
///   `DongleMonitor` found, rather than reusing the manager's object, which is
///   scheduled on the main run loop.
/// - The device runs on a dispatch queue ("hid.callbacks"), not a run loop.
///   The query is straight-line code with short waits, like the Python
///   script, and runs on `HeadsetReader`'s own queue. Input reports arrive on
///   the callback queue, go into a FIFO, and `read(timeout:)` waits on a
///   semaphore for the next one, which gives the same meaning as
///   `dev.read(LEN, ms)` in hidapi.
/// - It opens with `kIOHIDOptionsTypeNone`, without exclusive access, unlike
///   hidapi, which seizes the device. The headset's volume keys are expected
///   to keep working during a read, but that has not been tested.
/// - It is opened for one read and closed again; nothing stays open between
///   polls.
/// - The dongle has no `RequiresTCCAuthorization` property, so opening it is
///   not expected to need Input Monitoring. `IOHIDRequestAccess` is never
///   called, since it can show a prompt.
final class HIDTransport: HIDLink {
    let log: ((String) -> Void)?

    private let device: IOHIDDevice
    private let callbackQueue = DispatchQueue(label: "hid.callbacks")
    /// Where IOKit writes each input report. It must stay valid until the
    /// cancel handler has run, so it is freed in `deinit`, and only then.
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Frame.length)
    private let lock = NSLock()
    private var reports: [[UInt8]] = []
    private let available = DispatchSemaphore(value: 0)
    private let cancelled = DispatchSemaphore(value: 0)
    private var isOpen = false
    private var isActive = false
    /// False if the cancel handler did not run in time; the buffer is then
    /// leaked rather than freed while IOKit might still write to it.
    private var safeToFree = true

    /// Creates a device object for `service`. Returns nil if IOKit cannot.
    init?(service: io_service_t, log: ((String) -> Void)?) {
        guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { return nil }
        self.device = device
        self.log = log
    }

    deinit {
        if safeToFree {
            buffer.deallocate()
        }
    }

    /// Opens the device and starts receiving input reports.
    /// Returns nil on success, or why it failed.
    func open() -> OpenFailure? {
        IOHIDDeviceSetDispatchQueue(device, callbackQueue)
        IOHIDDeviceSetCancelHandler(device) { [cancelled] in cancelled.signal() }

        // C callbacks cannot capture `self`, so it is passed as a raw pointer.
        // The transport outlives the device's activity: `close()` waits for
        // the cancel handler before the transport can go away.
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device, buffer, Frame.length,
            { context, _, _, _, _, report, length in
                guard let context else { return }
                // The report starts with the report ID, like hidapi's.
                let bytes = Array(UnsafeBufferPointer(start: report, count: length))
                Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue().received(bytes)
            }, context)

        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDDeviceActivate(device)
        isActive = true
        guard result == kIOReturnSuccess else {
            return OpenFailure(code: result)
        }
        isOpen = true
        return nil
    }

    /// Closes the device and waits until IOKit has stopped using the buffer.
    func close() {
        if isOpen {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            isOpen = false
        }
        if isActive {
            IOHIDDeviceCancel(device)
            isActive = false
            if cancelled.wait(timeout: .now() + 2) == .timedOut {
                logError("cancel handler did not run; keeping the input buffer and the transport")
                safeToFree = false
                // IOKit may still call the input callback, which reaches this
                // object through an unretained pointer and writes to `buffer`.
                // Take one extra reference and never give it back, so both
                // stay valid for the rest of the process. A small, deliberate leak.
                _ = Unmanaged.passRetained(self)
            }
        }
    }

    // MARK: HIDLink

    func send(_ frame: Frame) -> Bool {
        let r = frame.bytes.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(frame.reportID), $0.baseAddress!, $0.count)
        }
        log?("TX (\(r == kIOReturnSuccess ? Frame.length : -1)): \(hex(frame.bytes.prefix(16))) ...")
        return r == kIOReturnSuccess
    }

    func read(timeout: TimeInterval) -> [UInt8]? {
        guard available.wait(timeout: .now() + timeout) == .success else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return reports.isEmpty ? nil : reports.removeFirst()
    }

    func sleep(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    // MARK: Input reports (run on the callback queue)

    private func received(_ report: [UInt8]) {
        lock.lock()
        reports.append(report)
        lock.unlock()
        available.signal()
    }
}

/// Writes a message to standard error, which ends up in Console.app for the
/// menu bar app and in the terminal for the command line options.
func logError(_ message: String) {
    FileHandle.standardError.write(Data("BlackSharkBattery: \(message)\n".utf8))
}
