// swift-tools-version: 6.2
import PackageDescription

// The Mac's half of the loop: a command-line executable that speaks MCP over
// stdio so Claude can read the user's training snapshot and write him a plan.
//
// It links `LiftingKit` and nothing else — no third-party packages at all. The
// MCP surface a local stdio server needs is six JSON-RPC methods, which is less
// code than the dependency graph an SDK would drag in (see
// `MCPProtocol.swift` for the note on that decision).
//
// `LiftingMCPKit` holds everything worth testing: the reports, the tool
// dispatch, and the JSON-RPC handling, none of which touch stdin or stdout.
// `lifting-mcp` is the thin shell that pumps bytes between the two.
let package = Package(
    name: "LiftingMCP",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "lifting-mcp", targets: ["lifting-mcp"])
    ],
    dependencies: [
        .package(path: "../LiftingKit")
    ],
    targets: [
        .target(
            name: "LiftingMCPKit",
            dependencies: [.product(name: "LiftingKit", package: "LiftingKit")],
            // The mark a client draws beside the connector. Bundled rather than
            // base64'd into a source file, for the same reason the catalog is a
            // resource: an asset is not code, and ten kilobytes of it in a
            // string literal is a file nobody can read or replace.
            resources: [.copy("Resources/superset-mark.png")],
            // Unlike LiftingKit, nothing consumes this package from Xcode, so
            // there is no `-suppress-warnings` to collide with and the
            // project's warnings-are-errors standard can be declared here.
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .executableTarget(
            name: "lifting-mcp",
            dependencies: ["LiftingMCPKit"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "LiftingMCPKitTests",
            dependencies: ["LiftingMCPKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
