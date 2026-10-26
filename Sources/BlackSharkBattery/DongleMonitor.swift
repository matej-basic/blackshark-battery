import BatteryCore
import Foundation
import IOKit.hid

/// Watches for the BlackShark V2 Pro 2.4 GHz dongle (USB 1532:0555) being
/// connected and disconnected.
///
/// It only asks the system to be told when the dongle comes and goes, and
/// reads its descriptive properties. It never opens the device; reading the
/// battery is `HIDTransport`'s job, once per poll.
final class DongleMonitor {
    /// Called on the main thread, about 300 ms after the last change, with
    /// one entry per physical dongle.
    var onChange: (([DongleInfo]) -> Void)?

    /// The dongles present right now, one per physical device.
    var devices: [DongleInfo] {
        devicesByIdentity.values.sorted { $0.identity < $1.identity }
    }

    /// The IOKit service of the first dongle, which `HIDTransport` opens.
    /// Nil when no dongle is connected.
    var service: io_service_t? {
        devices.first.flatMap { serviceOfIdentity[$0.identity] }
    }

    private let manager: IOHIDManager
    /// One entry per physical device.
    private var devicesByIdentity: [String: DongleInfo] = [:]
    /// The service of the first HID object seen for each physical device,
    /// retained with IOObjectRetain and released when the device goes away.
    private var serviceOfIdentity: [String: io_service_t] = [:]
    /// How many HID objects each physical device currently has. A device is
    /// only removed when its last object goes away.
    private var objectCount: [String: Int] = [:]
    /// Which physical device each HID object belongs to, so removal works
    /// even if the object's properties can no longer be read.
    private var identityOfObject: [UnsafeMutableRawPointer: String] = [:]
    private var pendingNotification: DispatchWorkItem?

    init() {
        // kIOHIDOptionsTypeNone: no special options.
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit {
        for service in serviceOfIdentity.values {
            IOObjectRelease(service)
        }
    }

    /// Starts watching. A dongle already connected is reported through the
    /// same callback as a new one, shortly after the run loop starts.
    func start() {
        let matching: [String: Int] = [
            kIOHIDVendorIDKey: 0x1532,
            kIOHIDProductIDKey: 0x0555,
            kIOHIDDeviceUsagePageKey: 0xFF00,  // matched against DeviceUsagePairs, not PrimaryUsagePage (which is 0x0C)
            kIOHIDDeviceUsageKey: 0x01,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        // C callbacks cannot capture `self`, so it is passed as a raw pointer.
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(
            manager,
            { context, _, _, device in
                guard let context else { return }
                Unmanaged<DongleMonitor>.fromOpaque(context).takeUnretainedValue().deviceAdded(device)
            }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(
            manager,
            { context, _, _, device in
                guard let context else { return }
                Unmanaged<DongleMonitor>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
            }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        // IOHIDManagerOpen is deliberately NOT called. The manager is only
        // for seeing the dongle; HIDTransport opens its own device object.

        // Report once even if no device matches at all.
        scheduleNotification()
    }

    // MARK: Callbacks (run on the main thread)

    private func deviceAdded(_ device: IOHIDDevice) {
        let pointer = Unmanaged.passUnretained(device).toOpaque()
        guard identityOfObject[pointer] == nil else { return }

        let info = Self.describe(device)
        identityOfObject[pointer] = info.identity
        objectCount[info.identity, default: 0] += 1
        if devicesByIdentity[info.identity] == nil {
            devicesByIdentity[info.identity] = info
            let service = IOHIDDeviceGetService(device)
            if service != IO_OBJECT_NULL, IOObjectRetain(service) == KERN_SUCCESS {
                serviceOfIdentity[info.identity] = service
            }
        }
        scheduleNotification()
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        let pointer = Unmanaged.passUnretained(device).toOpaque()
        guard let identity = identityOfObject.removeValue(forKey: pointer) else { return }

        let remaining = (objectCount[identity] ?? 1) - 1
        if remaining > 0 {
            objectCount[identity] = remaining
        } else {
            objectCount[identity] = nil
            devicesByIdentity[identity] = nil
            if let service = serviceOfIdentity.removeValue(forKey: identity) {
                IOObjectRelease(service)
            }
        }
        scheduleNotification()
    }

    /// Waits until devices have stopped changing for 300 ms, then reports.
    /// A hub or dock often announces several objects in a quick burst.
    private func scheduleNotification() {
        pendingNotification?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.onChange?(self.devices)
        }
        pendingNotification = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: Reading device properties

    /// Builds a DongleInfo from the properties of one HID object.
    static func describe(_ device: IOHIDDevice) -> DongleInfo {
        func property(_ key: String) -> CFTypeRef? {
            IOHIDDeviceGetProperty(device, key as CFString)
        }
        func number(_ key: String) -> Int? {
            (property(key) as? NSNumber)?.intValue
        }

        // LocationID is shared by all objects of one physical device. Devices
        // without it get an id unique to this object.
        let identity: String
        let location = number(kIOHIDLocationIDKey)
        if let location {
            identity = String(format: "location-0x%08x", location)
        } else {
            identity = "object-\(UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque()))"
        }

        var pairs: [UsagePair] = []
        if let list = property(kIOHIDDeviceUsagePairsKey) as? [[String: Any]] {
            for entry in list {
                if let page = (entry[kIOHIDDeviceUsagePageKey] as? NSNumber)?.intValue,
                    let usage = (entry[kIOHIDDeviceUsageKey] as? NSNumber)?.intValue
                {
                    pairs.append(UsagePair(page: page, usage: usage))
                }
            }
        }

        // RequiresTCCAuthorization is a registry property of the service,
        // not a HID device property, so it is read from the registry.
        var requiresTCC: Bool?
        let service = IOHIDDeviceGetService(device)
        if service != IO_OBJECT_NULL,
            let value = IORegistryEntryCreateCFProperty(service, "RequiresTCCAuthorization" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue()
        {
            requiresTCC = (value as? NSNumber)?.boolValue
        }

        return DongleInfo(
            identity: identity,
            locationID: location,
            vendorID: number(kIOHIDVendorIDKey),
            productID: number(kIOHIDProductIDKey),
            product: property(kIOHIDProductKey) as? String,
            transport: property(kIOHIDTransportKey) as? String,
            primaryUsagePage: number(kIOHIDPrimaryUsagePageKey),
            usagePairs: pairs,
            requiresTCC: requiresTCC
        )
    }
}
