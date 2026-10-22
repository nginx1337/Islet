// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Islet",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "Islet", targets: ["Islet"])
    ],
    targets: [
        // Pure logic without windows: adapter stream parsing, state machine, geometry,
        // position interpolation, marquee math, artwork colour, source failover.
        .target(
            name: "IsletCore",
            path: "Sources/IsletCore"
        ),
        // The app: menu bar item, island panels, SwiftUI views, data sources, settings.
        .executableTarget(
            name: "Islet",
            dependencies: ["IsletCore"],
            path: "Sources/Islet",
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ImageIO")
            ]
        ),
        .testTarget(
            name: "IsletCoreTests",
            dependencies: ["IsletCore"],
            path: "Tests/IsletCoreTests"
        )
    ]
)
