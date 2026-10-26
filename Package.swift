// swift-tools-version:5.9
import PackageDescription

// BatteryCore holds the protocol and the decision logic (the four output
// frames, the reply parser, the query sequence and when to poll). It uses
// Foundation only, so it and its tests build on Linux too. The menu bar app
// needs AppKit and IOKit, so it is only declared when the package is built
// on a Mac.
var targets: [Target] = [
    .target(
        name: "BatteryCore",
        path: "Sources/BatteryCore"
    ),
    .testTarget(
        name: "BatteryCoreTests",
        dependencies: ["BatteryCore"],
        path: "Tests/BatteryCoreTests"
    ),
]

#if os(macOS)
    targets.append(
        .executableTarget(
            name: "BlackSharkBattery",
            dependencies: ["BatteryCore"],
            path: "Sources/BlackSharkBattery"
        )
    )
#endif

let package = Package(
    name: "BlackSharkBattery",
    platforms: [.macOS(.v14)],
    targets: targets
)
