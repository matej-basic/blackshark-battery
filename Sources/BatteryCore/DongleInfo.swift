import Foundation

/// One HID usage pair, for example page 0x0C / usage 1 (Consumer Control)
/// or page 0xFF00 / usage 1 (the Razer vendor channel).
public struct UsagePair: Hashable, Codable, Sendable {
    public var page: Int
    public var usage: Int

    public init(page: Int, usage: Int) {
        self.page = page
        self.usage = usage
    }

    /// Vendor page 0xFF00 / usage 1. The dongle's battery protocol runs over
    /// this collection (report ID 2).
    public static let razerVendor = UsagePair(page: 0xFF00, usage: 1)
}

/// The dongle as the system reports it, reduced to the few properties the
/// app needs. The app fills this in from IOKit; tests fill it in by hand.
public struct DongleInfo: Hashable, Codable, Sendable {
    /// Stable id for one physical device. One physical device can show up as
    /// several HID objects, and they all share this id.
    public var identity: String
    /// The USB location, for example 0x20310000.
    public var locationID: Int?
    public var vendorID: Int?
    public var productID: Int?
    /// Product name, "Razer BlackShark V2 Pro 2.4".
    public var product: String?
    /// How it is connected, "USB" for the dongle.
    public var transport: String?
    /// The primary usage page. 0x0C (consumer) for the dongle, which is why
    /// the app matches on the usage pairs instead.
    public var primaryUsagePage: Int?
    public var usagePairs: [UsagePair]
    /// The `RequiresTCCAuthorization` property. Missing on the dongle, which
    /// is why opening it is not expected to need Input Monitoring.
    public var requiresTCC: Bool?

    public init(
        identity: String,
        locationID: Int? = nil,
        vendorID: Int? = nil,
        productID: Int? = nil,
        product: String? = nil,
        transport: String? = nil,
        primaryUsagePage: Int? = nil,
        usagePairs: [UsagePair] = [],
        requiresTCC: Bool? = nil
    ) {
        self.identity = identity
        self.locationID = locationID
        self.vendorID = vendorID
        self.productID = productID
        self.product = product
        self.transport = transport
        self.primaryUsagePage = primaryUsagePage
        self.usagePairs = usagePairs
        self.requiresTCC = requiresTCC
    }

    /// True when the device lists the vendor collection the protocol uses.
    public var hasVendorChannel: Bool {
        usagePairs.contains(.razerVendor)
    }
}
