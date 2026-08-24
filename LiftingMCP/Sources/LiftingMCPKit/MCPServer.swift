import Foundation

/// The JSON-RPC surface of MCP over stdio, as a pure function from one line in
/// to at most one line out.
///
/// Build one with a `ToolRunner` and feed it whole lines; `handle(line:)`
/// answers with the line to write back, or `nil` for a notification, which by
/// the protocol is never answered. It touches no file handles, which is what
/// makes the whole protocol testable without spawning a process.
///
/// **Why this is hand-written rather than an SDK.** The official Swift MCP SDK
/// builds and works, but it brings five external packages — one of them pinned
/// to a moving `main` branch — into a project that otherwise has none, to
/// implement six JSON-RPC methods over newline-delimited JSON. For a local tool
/// the owner builds once and relies on for months, a non-reproducible
/// dependency graph is the larger risk. Nothing here is clever; if the surface
/// ever grows past this file, that trade is worth revisiting.
///
/// A failure inside a tool comes back as a *tool result* with `isError`, not as
/// a JSON-RPC error. That is deliberate: a JSON-RPC error is handled by the
/// client and never reaches the model, so "that exercise ID does not exist"
/// would vanish exactly when the model needs to read it. JSON-RPC errors are
/// reserved for the protocol going wrong.
///
/// Depends on: `ToolRunner`, `ToolCatalog`, and `JSONValue`.
public struct MCPServer: Sendable {

    /// **The name a client shows beside the connector, and the app's own.** It
    /// was `liftingplan` — the Xcode project's name, which is not the product's
    /// and is not what anyone reading a connector list would recognise. The
    /// project, the bundle identifier and the iCloud container all keep the old
    /// name because renaming them orphans the container; nothing forces this to.
    public static let name = "Superset"
    /// What the connector says it is, under the name.
    public static let title = "Superset — your training log and plan writer"
    public static let version = "1.0.0"

    /// What a client shows for this connector: the name it keys on, the title a
    /// reader sees, and the mark beside it.
    ///
    /// **The icon is the app's own, taken from the app's own asset.** It is
    /// composed from the two layers of `Superset.icon` and filled with
    /// `Palette.accent`, so the connector cannot drift from the thing on the
    /// Home Screen — there is one mark and one copy of it.
    ///
    /// A `data:` URI rather than a link: a connector that has to fetch its own
    /// icon over the network is a connector that shows nothing when the network
    /// is not there, and this is seven kilobytes.
    static var serverInfo: JSONValue {
        var info: [String: JSONValue] = [
            "name": .string(name),
            "title": .string(title),
            "version": .string(version),
        ]
        if let mark = markDataURI {
            info["icons"] = .array([
                .object(["src": .string(mark), "mimeType": .string("image/png"),
                         "sizes": .array([.string("256x256")])])
            ])
        }
        return .object(info)
    }

    /// The mark as a `data:` URI, or `nil` when the resource cannot be found —
    /// which is a connector without a picture, not a connector that fails.
    private static let markDataURI: String? = {
        guard let url = Bundle.module.url(forResource: "superset-mark", withExtension: "png"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return "data:image/png;base64,\(data.base64EncodedString())"
    }()

    /// What this server answers with when the client asks for something it does
    /// not know. Every version listed is served by the same six methods; the
    /// differences between them do not reach a server this small.
    public static let preferredProtocolVersion = "2025-06-18"
    public static let supportedProtocolVersions = [
        "2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05",
    ]
    public static let contextResourceURI = "liftingplan://context"

    let runner: ToolRunner

    public init(runner: ToolRunner) {
        self.runner = runner
    }

    /// Answers one line of the protocol, or `nil` for a notification.
    ///
    /// Never throws and never fails to answer a request: a value that cannot be
    /// rendered as JSON — an infinity that reached a load in a corrupt
    /// snapshot, say — becomes an internal error, because a client left waiting
    /// for a reply that never comes is worse than one told the reply failed.
    public func handle(line: String) -> String? {
        let request: JSONValue
        do {
            request = try JSONValue.parse(Data(line.utf8))
        } catch {
            return Self.rendered(id: .null, .failure(.parseError, "That line is not JSON."))
        }

        // A request with no `id` is a notification and is never answered — not
        // even to complain about it.
        let id = request["id"]
        guard let method = request["method"]?.stringValue else {
            guard let id else { return nil }
            return Self.rendered(id: id, .failure(.invalidRequest, "No method was named."))
        }
        guard let id else { return nil }

        return Self.rendered(
            id: id, result(for: method, params: request["params"] ?? .object([:])))
    }

    // MARK: - The methods

    private func result(for method: String, params: JSONValue) -> RPCOutcome {
        switch method {
        case "initialize": .success(initialize(params))
        case "ping": .success([:])
        case "tools/list":
            .success(["tools": .array(ToolCatalog.definitions.map(\.advertised))])
        case "tools/call": callTool(params)
        case "resources/list": .success(["resources": [Self.contextResourceDescriptor]])
        case "resources/read": readResource(params)
        // Answered as empty rather than as "no such method": this server
        // declares neither capability, and a client that probes anyway gets a
        // plain answer instead of an error in the owner's log.
        case "resources/templates/list": .success(["resourceTemplates": []])
        case "prompts/list": .success(["prompts": []])
        default:
            .failure(.methodNotFound, "This server does not implement '\(method)'.")
        }
    }

    private func initialize(_ params: JSONValue) -> JSONValue {
        let requested = params["protocolVersion"]?.stringValue
        let agreed = requested.flatMap {
            Self.supportedProtocolVersions.contains($0) ? $0 : nil
        }
        return [
            "protocolVersion": .string(agreed ?? Self.preferredProtocolVersion),
            "capabilities": ["tools": [:], "resources": [:]],
            // `title` is what a client shows a human; `name` is what it keys
            // on. Both are sent, because a client that shows only the name must
            // still show something a reader recognises.
            "serverInfo": Self.serverInfo,
            "instructions": .string(Self.instructions),
        ]
    }

    private func callTool(_ params: JSONValue) -> RPCOutcome {
        guard let name = params["name"]?.stringValue else {
            return .failure(.invalidParams, "A tool call must name a tool.")
        }
        do {
            return .success(
                try Self.toolResult(
                    runner.call(name, arguments: params["arguments"] ?? .object([:]))))
        } catch {
            return .failure(.internalError, "That report could not be rendered as JSON: \(error)")
        }
    }

    private func readResource(_ params: JSONValue) -> RPCOutcome {
        guard params["uri"]?.stringValue == Self.contextResourceURI else {
            return .failure(
                .invalidParams,
                "This server has one resource, \(Self.contextResourceURI).")
        }
        let text: String
        do {
            switch runner.contextResource() {
            case .report(let report):
                text = try report.prettyEncoded()
            case .failure(let message):
                // A resource has no `isError`, so the explanation goes in the
                // body. Empty text would describe a user who does not exist.
                text = message
            }
        } catch {
            return .failure(.internalError, "The context could not be rendered as JSON: \(error)")
        }
        return .success([
            "contents": [[
                "uri": .string(Self.contextResourceURI),
                "mimeType": "application/json",
                "text": .string(text),
            ]]
        ])
    }

    // MARK: - Rendering

    /// A tool's answer in the shape `tools/call` returns.
    static func toolResult(_ outcome: ToolOutcome) throws -> JSONValue {
        switch outcome {
        case .report(let report):
            ["content": [["type": "text", "text": .string(try report.prettyEncoded())]]]
        case .failure(let message):
            ["content": [["type": "text", "text": .string(message)]], "isError": true]
        }
    }

    /// The envelope, on one line.
    ///
    /// The fallback is not a swallowed error: an envelope that cannot be
    /// rendered has already been reduced to a code and a plain string by the
    /// time it gets here, so the only remaining failure is one that would leave
    /// the client hanging. It answers instead.
    private static func rendered(id: JSONValue, _ outcome: RPCOutcome) -> String {
        let envelope: JSONValue = switch outcome {
        case .success(let result):
            ["jsonrpc": "2.0", "id": id, "result": result]
        case .failure(let code, let message):
            ["jsonrpc": "2.0", "id": id,
             "error": ["code": .integer(code.rawValue), "message": .string(message)]]
        }
        do {
            return try envelope.lineEncoded()
        } catch {
            return #"{"jsonrpc":"2.0","id":null,"error":"#
                + #"{"code":-32603,"message":"The reply could not be rendered as JSON."}}"#
        }
    }

    static let contextResourceDescriptor: JSONValue = [
        "uri": .string(contextResourceURI),
        "name": "user-context",
        "title": "User context",
        "description": .string(
            "Who the user is, what equipment and constraints he has, the block he is on, "
                + "what he trained lately, and the weight he is currently working with on "
                + "each lift."),
        "mimeType": "application/json",
    ]

    static let instructions = """
        This server reports on one user's training and writes plans for him. \
        Read the \(contextResourceURI) resource first; it is small and says who \
        he is, what he has to train with, and what he did lately.

        Every tool here reports and none of them concludes. There is no tool \
        that suggests a progression or judges whether a program is balanced, \
        because those are your calls to make from the data, not the server's.

        **The app asks him nothing.** It has no setup screen and no form; you \
        are the interface. A fact that reads as null is one nobody has stated, \
        not a default and not an empty answer — never assume a value for one. \
        When he tells you something standing — his gym, an injury, when he can \
        train — write it down with \(ToolCatalog.updateNotes), or the next \
        conversation starts from nothing again. That tool merges: send only \
        what you just learned.

        **The record holds no facts about him at all, and that is deliberate.** \
        Who he is lives in `ACCOUNT.md` — his objective, his background, his \
        injuries, what he avoids and why, his equipment, his bodyweight. Read it \
        before writing a plan. An unwritten note reads as its template, so \
        "_Not yet stated._" under a heading is the record telling you nobody has \
        asked.

        Always take exercise IDs from \(ToolCatalog.listExercises) verbatim. \
        \(ToolCatalog.writePlan) rejects an ID the catalog does not have, \
        because training history is keyed on exercise identity.
        """
}

/// What one JSON-RPC method call produced.
private enum RPCOutcome {
    case success(JSONValue)
    case failure(RPCErrorCode, String)
}

/// The JSON-RPC 2.0 codes this server uses.
enum RPCErrorCode: Int {
    case parseError = -32700
    case invalidRequest = -32600
    case methodNotFound = -32601
    case invalidParams = -32602
    case internalError = -32603
}
