// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MacVitals",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "macvitals", targets: ["macvitals"]),
        .library(name: "MacVitalsCore", targets: ["MacVitalsCore"]),
    ],
    targets: [
        // Everything testable lives here: collectors, analysis, report rendering, delivery.
        .target(name: "MacVitalsCore"),
        // Thin CLI / launchd entry points (daemon, menu bar agent, admin commands).
        .executableTarget(name: "macvitals", dependencies: ["MacVitalsCore"]),
        .testTarget(name: "MacVitalsCoreTests", dependencies: ["MacVitalsCore"]),
    ]
)
