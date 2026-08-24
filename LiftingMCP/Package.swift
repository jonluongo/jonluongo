// swift-tools-version: 6.2
import PackageDescription

// The Mac's half of the loop: a command-line executable that speaks MCP over
// stdio so Claude can read the user's training snapshot and write him a plan.
//
// **Two shells over one core.** `lifting-mcp` speaks stdio for local work;
// `superset-server` speaks HTTP so a phone can reach it. Only the second takes
// a third-party package, and it takes exactly one.
//
// `LiftingMCPKit` links `LiftingKit` and nothing else — no third-party
// packages at all, which is what keeps it portable and quick to build. The
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
        .executable(name: "lifting-mcp", targets: ["lifting-mcp"]),
        .executable(name: "superset-server", targets: ["superset-server"]),
    ],
    dependencies: [
        .package(path: "../LiftingKit"),
        // **The one third-party package, and it is held at arm's length.** It
        // is a dependency of the `superset-server` shell only: `LiftingMCPKit`
        // still links nothing but LiftingKit, so the whole testable core builds
        // and runs without it.
        //
        // **swift-nio rather than a framework, and the numbers decided it.**
        // Hummingbird was recommended first on the belief that its graph was
        // small; resolved, it is 24 packages — TLS, HTTP/2, certificates,
        // ASN.1, crypto, an HTTP *client*, tracing, metrics — for one POST
        // endpoint that sits behind a proxy already terminating TLS. This is
        // four, all from `apple/`, which is *fewer than the five* that got the
        // official MCP SDK rejected in `MCPServer`'s own comment. `NIOHTTP1`
        // brings the HTTP/1.1 codec, so nothing here parses HTTP by hand; what
        // is written is a pipeline, and `HTTPEndpoint` already holds every rule.
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.101.0"),
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
        // The HTTP shell. It holds no rules: `HTTPEndpoint` decides every one
        // of them without a socket, and this pumps bytes to it — the same
        // division `lifting-mcp` has, so the two shells stay comparable.
        .executableTarget(
            name: "superset-server",
            dependencies: [
                "LiftingMCPKit",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "LiftingMCPKitTests",
            dependencies: ["LiftingMCPKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
