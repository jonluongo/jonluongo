import Foundation
import LiftingKit
import LiftingMCPKit

/// The executable Claude Desktop launches: a pipe between stdin, stdout and
/// `MCPServer`.
///
/// It reads newline-delimited JSON-RPC from standard input and writes one line
/// of JSON per answered request to standard output. **Nothing else may ever be
/// written to standard output** — a stray `print` is indistinguishable from a
/// protocol message and breaks the session. Everything diagnostic goes to
/// standard error, which the client shows in its log.
///
/// All the behaviour lives in `LiftingMCPKit`; this file only moves bytes, and
/// is the one part of the server that a test cannot reach.
///
/// Depends on: `ServerConfiguration`, `DocumentFolder` from `LiftingKit`,
/// `ToolRunner` and `MCPServer`.
@main
struct LiftingMCPTool {

    static func main() {
        do {
            let configuration = try ServerConfiguration.resolve(
                arguments: CommandLine.arguments,
                environment: ProcessInfo.processInfo.environment,
                home: URL.homeDirectory
            )
            // A build defect, not a user state: an unreadable catalog would make
            // every exercise ID look invalid, so it fails at launch and loudly
            // rather than at the first tool call and confusingly.
            let catalog = try ExerciseCatalog.bundled()

            log(
                "Superset MCP server ready. Catalog version \(catalog.version), "
                    + "\(catalog.all.count) exercises. Documents: "
                    + "\(configuration.documentsDirectory.path(percentEncoded: false))"
                    + (configuration.isDefaultLocation ? " (default iCloud location)" : ""))

            let server = MCPServer(
                runner: ToolRunner(
                    documents: DocumentFolder(directory: configuration.documentsDirectory),
                    catalog: catalog))
            try pump(server)
        } catch {
            log("Superset MCP server could not start: \(error.localizedDescription)")
            exit(EXIT_FAILURE)
        }
    }

    /// Reads requests until standard input closes, which is how the client says
    /// the session is over.
    private static func pump(_ server: MCPServer) throws {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let response = server.handle(line: line) else { continue }
            try emit(response)
        }
    }

    /// Writes one message and its newline.
    ///
    /// Straight to the file descriptor rather than through `print`, whose
    /// buffering is line-based on a terminal and block-based on a pipe — and a
    /// pipe is exactly what Claude Desktop gives it. A buffered reply is a reply
    /// the client waits forever for.
    private static func emit(_ line: String) throws {
        try FileHandle.standardOutput.write(contentsOf: Data((line + "\n").utf8))
    }

    /// A diagnostic line, on standard error where it cannot corrupt the
    /// protocol.
    ///
    /// `fputs` rather than a `FileHandle`, so there is no error to either
    /// propagate or discard: there is nowhere for a logging failure to go, and
    /// swallowing a thrown one would be exactly the thing this project does not
    /// do.
    private static func log(_ message: String) {
        fputs(message + "\n", stderr)
    }
}
