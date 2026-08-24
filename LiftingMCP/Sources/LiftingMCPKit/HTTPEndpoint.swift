import Foundation

/// What an MCP request over HTTP answers with, as a pure function from one
/// request to one response.
///
/// **What it does.** Turns a method, a path, a body and headers into a status,
/// headers and a body — the whole of MCP's Streamable HTTP transport that this
/// server needs, and none of the socket handling.
///
/// **Why it is separate from any HTTP server.** `MCPServer` is a pure function
/// from one line to one line and touches no file handles, which is what makes
/// the protocol testable without spawning a process. This is the same trick one
/// layer out: every rule about what an HTTP client may send and what it gets
/// back is decided here, tested here, and owes nothing to whichever library
/// eventually opens the port. That library is a dependency decision this
/// project has not made — it has none — and the decision stays open while the
/// work that is genuinely ours gets done.
///
/// **How it is used.** Build one with an `MCPServer` and an `Authorization`,
/// hand it a request, and write back what it answers. A socket adapter is the
/// only thing left, and it holds no rules.
///
/// **What it depends on.** `MCPServer` and Foundation. It reads no files, opens
/// no ports, and keeps no state between requests — the server is stateless by
/// design, so there is nothing for a session to hold.
public struct HTTPEndpoint: Sendable {

    /// The path MCP is served at.
    public static let path = "/mcp"

    /// Whether a request is allowed to reach the tools at all.
    ///
    /// **A seam, deliberately unfilled.** Fly gives HTTPS, not authorisation,
    /// and an open URL is a stranger's training log that `write_plan` will let
    /// them prescribe into. What guards it — a bearer token, OAuth — is Jon's
    /// to rule on, and the shape of that ruling changes nothing here. What
    /// matters is that the decision is *representable* rather than forgotten:
    /// a build with no answer has to say so out loud.
    public protocol Authorization: Sendable {

        /// Whether these headers may proceed. Header names arrive lowercased.
        func permits(headers: [String: String]) -> Bool
    }

    /// The answer to one request.
    public struct Response: Equatable, Sendable {

        public let status: Int
        public let headers: [String: String]
        public let body: String

        public init(status: Int, headers: [String: String] = [:], body: String = "") {
            self.status = status
            self.headers = headers
            self.body = body
        }
    }

    private let server: MCPServer
    private let authorization: any Authorization
    private let resource: ProtectedResource?

    /// - Parameter resource: this server's OAuth identity, or `nil` when no
    ///   authorization server has been configured.
    ///
    ///   **`nil` publishes nothing and promises nothing.** A metadata document
    ///   naming an issuer that does not answer sends a client into a flow it
    ///   cannot finish, and the challenge would say *go here* to an address with
    ///   nothing behind it. That is a document promising behaviour the code does
    ///   not have — the defect this project has spent a week removing — so the
    ///   server declines to publish rather than publish a hope. Without one it
    ///   still demands a credential; it simply does not claim to be doing OAuth.
    public init(
        server: MCPServer, authorization: any Authorization,
        resource: ProtectedResource? = nil
    ) {
        self.server = server
        self.authorization = authorization
        self.resource = resource
    }

    /// The response to one HTTP request.
    ///
    /// **A refused request is refused before it is read.** Authorisation is
    /// asked first, so an unauthorised body is never parsed and never reaches a
    /// tool — which matters because `write_plan` writes.
    ///
    /// **A JSON-RPC error is not an HTTP error.** A tool that refuses a plan
    /// answers `200` with `isError` in the result, exactly as it does over
    /// stdio: the refusal is written for the coach and has to reach him, and a
    /// `4xx` would be handled by his client instead. HTTP statuses here are
    /// only about the transport — wrong path, wrong method, no credential.
    ///
    /// **A notification is answered `202` with nothing**, because by the
    /// protocol it is never answered at all, and a client left holding an empty
    /// `200` cannot tell that from a reply it failed to parse.
    public func response(
        method: String, path: String, headers: [String: String] = [:], body: String
    ) -> Response {
        let headers = Dictionary(
            headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })

        // **Discovery is answered before the credential is asked for**, because
        // it is how a client learns to get one. Guarding it would be a locked
        // door with the instructions for opening it locked inside — and it
        // reveals nothing: the document holds this server's own address and its
        // issuer's, both of which a client already knows enough to ask for.
        if let resource, resource.metadataPaths.contains(path) {
            guard method.uppercased() == "GET" else {
                return Response(
                    status: 405, headers: ["allow": "GET", "content-type": "application/json"],
                    body: Self.transportError("This document is read with GET."))
            }
            return Response(
                status: 200,
                headers: ["content-type": "application/json",
                          // A public document that changes only on redeploy.
                          "cache-control": "public, max-age=3600"],
                body: (try? resource.metadata.lineEncoded()) ?? "{}")
        }

        guard authorization.permits(headers: headers) else {
            // **Named as the protocol asks.** A bare `Bearer` tells a client it
            // was refused and nothing about how to come back, so a connector
            // cannot begin a flow it has no way to discover. This carries the
            // address of the metadata document and the scope to ask for, which
            // is what RFC 9728 and the MCP specification require.
            guard let resource else {
                // No issuer configured, so there is nowhere to send a client and
                // saying `Bearer` alone is the whole truth.
                return Response(
                    status: 401,
                    headers: ["www-authenticate": "Bearer", "content-type": "application/json"],
                    body: Self.transportError("This server needs a credential."))
            }
            return Response(
                status: 401,
                headers: ["www-authenticate": resource.challenge,
                          "content-type": "application/json"],
                body: Self.transportError(
                    "This server needs a credential. Read "
                        + "\(resource.metadataURL.absoluteString) to discover how to get one."))
        }
        guard path == Self.path else {
            return Response(
                status: 404, headers: ["content-type": "application/json"],
                body: Self.transportError("MCP is served at \(Self.path)."))
        }
        guard method.uppercased() == "POST" else {
            // GET is what a client opens an event stream with. This server
            // never speaks first — it has no subscriptions and no progress to
            // report — so there is nothing for a stream to carry, and saying so
            // is better than holding one open that will never say anything.
            return Response(
                status: 405,
                headers: ["allow": "POST", "content-type": "application/json"],
                body: Self.transportError(
                    "This server answers POST only: it never speaks first, so there is no "
                        + "event stream to open."))
        }
        guard let answer = server.handle(line: body) else {
            return Response(status: 202)
        }
        return Response(
            status: 200, headers: ["content-type": "application/json"], body: answer)
    }

    /// A JSON-RPC error for a failure of the transport rather than of a tool.
    ///
    /// It carries a null `id` because a request that was refused for its path,
    /// its method or its credential was never parsed, so there is no id to
    /// answer — and inventing one would answer a request nobody made.
    private static func transportError(_ message: String) -> String {
        let error: JSONValue = [
            "jsonrpc": "2.0", "id": .null,
            "error": ["code": .integer(RPCErrorCode.invalidRequest.rawValue),
                      "message": .string(message)],
        ]
        // The fallback cannot arise — the envelope is two integers and a string
        // this file wrote — but a transport that throws while explaining itself
        // would leave a client with nothing at all.
        return (try? error.lineEncoded())
            ?? #"{"jsonrpc":"2.0","id":null,"error":{"code":-32600,"message":"Refused."}}"#
    }
}
