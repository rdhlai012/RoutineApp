// swift-tools-version:5.7
import PackageDescription

// RoutineKit is the Foundation-only core of the app: models, date/time maths,
// prayer-anchor resolution, the notification planner, sleep maths, stats and
// JSON migration. It imports neither SwiftUI nor UserNotifications, so `swift
// test` runs it anywhere - including CI without a simulator.
//
// The iOS app target (see project.yml) compiles these same sources directly;
// there is exactly one copy of this code.
let package = Package(
    name: "RoutineKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v12)
    ],
    products: [
        .library(name: "RoutineKit", targets: ["RoutineKit"])
    ],
    targets: [
        .target(name: "RoutineKit", path: "Sources/RoutineKit"),
        .testTarget(
            name: "RoutineKitTests",
            dependencies: ["RoutineKit"],
            path: "Tests/RoutineKitTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
