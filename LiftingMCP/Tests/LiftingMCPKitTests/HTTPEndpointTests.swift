import Foundation
import Testing
import LiftingKit
@testable import LiftingMCPKit

/// What MCP over HTTP answers, decided without a socket.
///
/// **The point of the seam is that these run at all.** Every rule about what a
/// client may send and what comes back is settled here, so whichever library
/// eventually opens the port inherits no decisions — and the dependency that
/// library represents, in a project that has none, stays an open question while
/// the work that is ours gets finished.
@Suite("MCP over HTTP")
struct HTTPEndpointTests {

    /// Lets everything through, so a test about paths is not also a test about
    /// credentials.
    private struct OpenDoor: HTTPEndpoint.Authorization {
        func permits(headers: [String: String]) -> Bool { true }
    }

    /// Refuses everything, for the mirror.
    private struct Locked: HTTPEndpoint.Authorization {
        func permits(headers: [String: String]) -> Bool { false }
    }

    /// Accepts one bearer token, which is the cheap shape the spec leaves open.
    private struct Bearer: HTTPEndpoint.Authorization {
        let token: String
        func permits(headers: [String: String]) -> Bool {
            headers["authorization"] == "Bearer \(token)"
        }
    }

    private static let resource = ProtectedResource(
        resource: URL(string: "https://superset.fly.dev/mcp")!,
        authorizationServers: [URL(string: "https://issuer.example")!])

    private func endpoint(
        _ authorization: any HTTPEndpoint.Authorization = OpenDoor(),
        resource: ProtectedResource? = HTTPEndpointTests.resource
    ) throws -> HTTPEndpoint {
        HTTPEndpoint(
            server: MCPServer(
                runner: try makeRunner(documents: InMemoryDocuments(snapshot: fixtureSnapshot()))),
            authorization: authorization, resource: resource)
    }

    private var initialize: String {
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"#
            + #""2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}"#
    }

    // MARK: - The happy path

    @Test("A posted request comes back as JSON on 200")
    func aRequestIsAnswered() throws {
        let answer = try endpoint().response(
            method: "POST", path: "/mcp", body: initialize)

        #expect(answer.status == 200)
        #expect(answer.headers["content-type"] == "application/json")
        #expect(answer.body.contains("serverInfo"))
        #expect(answer.body.contains("Superset"))
    }

    @Test("A notification is answered 202 with nothing, not an empty 200")
    func aNotificationIsNotAnswered() throws {
        // By the protocol a notification is never answered. An empty `200` is
        // indistinguishable from a reply the client failed to parse.
        let answer = try endpoint().response(
            method: "POST", path: "/mcp",
            body: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)

        #expect(answer.status == 202)
        #expect(answer.body.isEmpty)
    }

    @Test("A tool that refuses still answers 200, so the refusal reaches its author")
    func aRefusalIsNotAnHTTPError() throws {
        // **The rule this endpoint exists to not break.** A refusal is written
        // for the coach and has to reach him; a 4xx is handled by his client
        // and never becomes something he can read.
        let call = #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":"#
            + #"{"name":"exercise_history","arguments":{"id":"not-a-real-exercise"}}}"#
        let answer = try endpoint().response(method: "POST", path: "/mcp", body: call)

        #expect(answer.status == 200)
        #expect(answer.body.contains("isError"))
    }

    @Test("Malformed JSON is a JSON-RPC parse error on 200, not a 400")
    func badJSONIsAnsweredNotRejected() throws {
        let answer = try endpoint().response(method: "POST", path: "/mcp", body: "{not json")

        #expect(answer.status == 200, "the transport worked; the payload did not")
        #expect(answer.body.contains("-32700") || answer.body.contains("not JSON"))
    }

    // MARK: - The transport's own failures

    @Test("Another path is 404 and says where MCP lives")
    func theWrongPathIsNamed() throws {
        let answer = try endpoint().response(method: "POST", path: "/", body: initialize)

        #expect(answer.status == 404)
        #expect(answer.body.contains("/mcp"))
    }

    @Test("GET is 405 with Allow, because this server never speaks first")
    func thereIsNoEventStream() throws {
        // A client opens an event stream with GET. This server has no
        // subscriptions and no progress to report, so a stream would be held
        // open forever saying nothing.
        let answer = try endpoint().response(method: "GET", path: "/mcp", body: "")

        #expect(answer.status == 405)
        #expect(answer.headers["allow"] == "POST")
    }

    @Test("The method is read without regard to case")
    func lowercaseMethodIsStillPost() throws {
        #expect(try endpoint().response(method: "post", path: "/mcp", body: initialize).status == 200)
    }

    // MARK: - The credential

    @Test("Without a credential nothing is answered, and the body is never read")
    func anUnauthorisedRequestIsRefused() throws {
        // Refused before parsing, which is what matters: `write_plan` writes,
        // and an open URL is a stranger prescribing into Jon's training log.
        let write = #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":"#
            + #"{"name":"write_plan","arguments":{"sessions":[]}}}"#
        let answer = try endpoint(Locked()).response(method: "POST", path: "/mcp", body: write)

        #expect(answer.status == 401)
        // The challenge names the metadata document rather than being a bare
        // `Bearer`; the case with no issuer configured is asserted separately.
        #expect(answer.headers["www-authenticate"]?.hasPrefix("Bearer resource_metadata=") == true)
    }

    @Test("A credential is refused before the path is, so a probe reaches no tool")
    func authorisationComesFirst() throws {
        // **This used to assert that the 401 named no path at all**, which
        // stopped being the right test when discovery landed: RFC 9728 exists to
        // *publish* the resource URI, so naming it is the specification working
        // rather than a leak. What still matters — and is what this was really
        // for — is that an unauthorised request never reaches a tool and is
        // never parsed, whatever path it asks for.
        let answer = try endpoint(Locked()).response(
            method: "GET", path: "/admin", body: "")

        #expect(answer.status == 401, "not 404 and not 405: it is refused before it is read")
        #expect(!answer.body.contains("serverInfo"), "no tool answered it")
    }

    @Test("A bearer token is read case-insensitively from the header name")
    func headerNamesAreNotCaseSensitive() throws {
        // HTTP header names are case-insensitive and libraries disagree about
        // how they hand them over. A rule that depends on which one opened the
        // port is a rule that breaks when the port is opened differently.
        let end = try endpoint(Bearer(token: "hunter2"))

        #expect(end.response(
            method: "POST", path: "/mcp",
            headers: ["Authorization": "Bearer hunter2"], body: initialize).status == 200)
        #expect(end.response(
            method: "POST", path: "/mcp",
            headers: ["AUTHORIZATION": "Bearer hunter2"], body: initialize).status == 200)
        #expect(end.response(
            method: "POST", path: "/mcp",
            headers: ["authorization": "Bearer wrong"], body: initialize).status == 401)
        #expect(end.response(
            method: "POST", path: "/mcp", body: initialize).status == 401)
    }

    // MARK: - Discovering how to authenticate

    @Test("The metadata document is served without a credential")
    func discoveryIsNotBehindTheDoor() throws {
        // **The one thing that must not be guarded.** It is how a client learns
        // to get a credential; requiring one to read it is a locked door with
        // the key inside. It reveals nothing either — this server's address and
        // its issuer's, both of which a caller already knows enough to ask for.
        let answer = try endpoint(Locked()).response(
            method: "GET", path: "/.well-known/oauth-protected-resource/mcp", body: "")

        #expect(answer.status == 200)
        #expect(answer.body.contains("https://superset.fly.dev/mcp"))
        #expect(answer.body.contains("https://issuer.example"))
    }

    @Test("Both the RFC's path and the bare one answer, because clients try both")
    func eitherAddressFinds() throws {
        // RFC 9728 inserts the well-known segment before the resource's path;
        // the MCP specification's example shows the bare form. The document is
        // identical, and discovery that fails is worse than one served twice.
        for path in ["/.well-known/oauth-protected-resource/mcp",
                     "/.well-known/oauth-protected-resource"] {
            #expect(try endpoint().response(method: "GET", path: path, body: "").status == 200,
                    "\(path)")
        }
    }

    @Test("The 401 names where to discover the issuer and what scope to ask for")
    func theChallengeIsActionable() throws {
        let answer = try endpoint(Locked()).response(
            method: "POST", path: "/mcp", body: initialize)
        let challenge = try #require(answer.headers["www-authenticate"])

        #expect(answer.status == 401)
        #expect(challenge.contains(#"resource_metadata="https://superset.fly.dev"#))
        #expect(challenge.contains(#"scope="training""#))
    }

    @Test("The address in the challenge is the address that answers")
    func theSignPointsAtTheDoor() throws {
        // Two derivations of one value would eventually disagree, and a client
        // sent to the wrong address cannot tell that from a server that is down.
        let challenge = try #require(
            try endpoint(Locked())
                .response(method: "POST", path: "/mcp", body: initialize)
                .headers["www-authenticate"])
        let quoted = try #require(challenge
            .split(separator: "\"").dropFirst().first.map(String.init))
        let path = try #require(URL(string: quoted)?.path())

        #expect(try endpoint().response(method: "GET", path: path, body: "").status == 200)
    }

    @Test("With no issuer configured the server publishes nothing and claims nothing")
    func nothingIsPromisedThatIsNotThere() throws {
        // A metadata document naming an issuer that does not answer sends a
        // client into a flow it cannot finish. Saying `Bearer` alone is then the
        // whole truth.
        let bare = try endpoint(Locked(), resource: nil)

        #expect(bare.response(
            method: "GET", path: "/.well-known/oauth-protected-resource", body: "").status == 401,
            "not 200: there is no document to serve")
        #expect(bare.response(
            method: "POST", path: "/mcp", body: initialize)
            .headers["www-authenticate"] == "Bearer")
    }

    @Test("The metadata document is read, not posted to")
    func discoveryIsReadOnly() throws {
        let answer = try endpoint().response(
            method: "POST", path: "/.well-known/oauth-protected-resource/mcp", body: "{}")

        #expect(answer.status == 405)
        #expect(answer.headers["allow"] == "GET")
    }
}
