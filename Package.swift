// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BatteryWarning",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BatteryWarning", targets: ["BatteryWarning"]),
        .library(name: "BatteryWarningKit", targets: ["BatteryWarningKit"])
    ],
    targets: [
        // Core logic: status reading, thresholds, login registration.
        // Free of window and view code, so it is unit testable directly.
        .target(
            name: "BatteryWarningKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // AppKit shell: status item, alert panel, menus.
        .executableTarget(
            name: "BatteryWarning",
            dependencies: ["BatteryWarningKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BatteryWarningKitTests",
            dependencies: ["BatteryWarningKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)