import BatteryCore
import Foundation
import IOKit

/// Runs reads of the headset one at a time on a serial queue ("hid.io"), so
/// the blocking query never runs on the main thread and two reads never
/// overlap.
final class HeadsetReader {
    /// Where `-v` frame logging goes, or nil when it is off.
    let log: ((String) -> Void)?

    private let ioQueue = DispatchQueue(label: "hid.io")

    init(log: ((String) -> Void)?) {
        self.log = log
    }

    /// Opens the dongle at `service`, reads level and charging state, closes
    /// it again, and then calls `completion` on the io queue with the outcome.
    func read(service: io_service_t, completion: @escaping (ReadOutcome) -> Void) {
        withOpenTransport(service: service) { result in
            switch result {
            case .success(let transport): return readHeadset(on: transport)
            case .failure(.noDongle): return .noDongle
            case .failure(.openFailed(let failure)): return .openFailed(failure)
            }
        } completion: { outcome in
            completion(outcome)
        }
    }

    /// Opens the dongle, sends nothing, and passes every input report that
    /// arrives within `seconds` to `onReport`. Calls `completion` on the io
    /// queue with the number of reports, or with the reason opening failed.
    func listen(
        service: io_service_t, seconds: TimeInterval, onReport: @escaping ([UInt8]) -> Void,
        completion: @escaping (Result<Int, OpenError>) -> Void
    ) {
        withOpenTransport(service: service) { result in
            result.map { transport in
                let end = transport.now() + seconds
                var count = 0
                while transport.now() < end {
                    if let report = transport.read(timeout: 0.2), !report.isEmpty {
                        count += 1
                        onReport(report)
                    }
                }
                return count
            }
        } completion: { result in
            completion(result)
        }
    }

    /// Why no open transport could be handed to a read.
    enum OpenError: Error, Equatable {
        /// IOKit could not make a device object, for example after an unplug.
        case noDongle
        case openFailed(OpenFailure)
    }

    /// On the io queue: creates and opens a transport, runs `body` with it,
    /// always closes it again, and only then calls `completion`.
    private func withOpenTransport<T>(
        service: io_service_t, _ body: @escaping (Result<HIDTransport, OpenError>) -> T, completion: @escaping (T) -> Void
    ) {
        // Keep the service alive for the read, even if the dongle is
        // unplugged and the monitor releases its reference meanwhile.
        IOObjectRetain(service)
        ioQueue.async { [log] in
            defer { IOObjectRelease(service) }
            guard let transport = HIDTransport(service: service, log: log) else {
                completion(body(.failure(.noDongle)))
                return
            }
            let value: T
            if let failure = transport.open() {
                value = body(.failure(.openFailed(failure)))
            } else {
                value = body(.success(transport))
            }
            transport.close()
            completion(value)
        }
    }
}
