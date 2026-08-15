// swift-tools-version: 6.2
import PackageDescription

// The shared vocabulary of LiftingPlan: what an exercise is, what a weight is,
// and what the bundled catalog contains.
//
// Two clients depend on this — the iOS app and (from Task 2) a macOS MCP server
// — so neither can disagree about any of it. Deliberately excluded: the
// SwiftData models, which stay in the app. The server reads a snapshot file and
// must never link SwiftData.
//
// Inside `Sources/LiftingKit`, `Domain/` imports only Foundation and `Catalog/`
// imports only `Domain/`. Neither imports SwiftData or SwiftUI.
let package = Package(
    name: "LiftingKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "LiftingKit", targets: ["LiftingKit"])
    ],
    // Warnings-as-errors is deliberately NOT declared here. Xcode compiles a
    // package dependency with `-suppress-warnings`, and a manifest-level
    // `.treatAllWarnings(as: .error)` collides with it — the app then fails to
    // build with "conflicting options '-warnings-as-errors' and
    // '-suppress-warnings'". Enforce the project's standard on the package with
    //
    //     swift build --package-path LiftingKit -Xswiftc -warnings-as-errors
    //
    // which is checked alongside `swift test`. The app target keeps
    // SWIFT_TREAT_WARNINGS_AS_ERRORS = YES either way.
    targets: [
        .target(
            name: "LiftingKit",
            resources: [.process("Catalog/Resources")]
        ),
        .testTarget(
            name: "LiftingKitTests",
            dependencies: ["LiftingKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
