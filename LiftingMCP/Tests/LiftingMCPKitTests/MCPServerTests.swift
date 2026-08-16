import Foundation
import Testing
import LiftingKit
@testable import LiftingMCPKit

@Suite("MCP over stdio")
struct MCPServerTests {

    private func makeServer(snapshot: TrainingSnapshot? = fixtureSnapshot()) throws -> MCPServer {
        MCPServer(runner: try makeRunner(documents: InMemoryDocuments(snapshot: snapshot)))
    }

    private func ask(_ server: MCPServer, _ request: JSONValue) throws -> JSONValue? {
        guard let line = server.handle(line: try request.lineEncoded()) else { return nil }
        #expect(!line.contains("\n"), "a message with a newline in it ends early on the wire")
        return try JSONValue.parse(Data(line.utf8))
    }

    private func request(_ method: String, _ params: JSONValue = [:], id: JSONValue = 1)
        -> JSONValue
    {
        ["jsonrpc": "2.0", "id": id, "method": .string(method), "params": params]
    }

    // MARK: - The handshake

    @Test("initialize answers with a protocol version, capabilities and a name")
    func initializeHandshake() throws {
        let response = try #require(try ask(try makeServer(), request(
            "initialize",
            ["protocolVersion": "2025-06-18",
             "capabilities": [:],
             "clientInfo": ["name": "claude-desktop", "version": "1.0"]])))
        let result = try #require(response["result"])

        #expect(response["jsonrpc"]?.stringValue == "2.0")
        #expect(response["id"] == 1)
        #expect(result["protocolVersion"]?.stringValue == "2025-06-18")
        #expect(result["capabilities"]?["tools"] != nil)
        #expect(result["capabilities"]?["resources"] != nil)
        #expect(result["serverInfo"]?["name"]?.stringValue == MCPServer.name)
    }

    @Test("A protocol version this server does not know is answered with one it does")
    func unknownProtocolVersionFallsBack() throws {
        let response = try #require(try ask(try makeServer(), request(
            "initialize", ["protocolVersion": "1999-01-01"])))

        #expect(response["result"]?["protocolVersion"]?.stringValue
            == MCPServer.preferredProtocolVersion)
    }

    @Test("A notification is not answered at all")
    func notificationsGetNoReply() throws {
        let server = try makeServer()
        let notification: JSONValue = ["jsonrpc": "2.0", "method": "notifications/initialized"]

        #expect(server.handle(line: try notification.lineEncoded()) == nil)
    }

    @Test("ping answers, so a client can tell the server is alive")
    func pingAnswers() throws {
        #expect(try ask(try makeServer(), request("ping"))?["result"] != nil)
    }

    // MARK: - The tools

    @Test("tools/list advertises exactly the seven tools, each with a schema")
    func toolsListIsComplete() throws {
        let tools = try #require(
            try ask(try makeServer(), request("tools/list"))?["result"]?["tools"]?.arrayValue)
        let names = tools.compactMap { $0["name"]?.stringValue }.sorted()

        #expect(names == [
            "exercise_history", "list_exercises", "recent_sessions", "unstated_facts",
            "update_profile", "volume_by_muscle", "write_plan",
        ])
        #expect(tools.allSatisfy { $0["inputSchema"]?["type"]?.stringValue == "object" })
        #expect(tools.allSatisfy { $0["description"]?.stringValue?.isEmpty == false })
    }

    @Test("No tool concludes anything about training — that is Claude's job, not the server's")
    func nothingRecommends() throws {
        let tools = try #require(
            try ask(try makeServer(), request("tools/list"))?["result"]?["tools"]?.arrayValue)
        let names = tools.compactMap { $0["name"]?.stringValue }

        #expect(!names.contains("suggest_progression"))
        #expect(!names.contains("check_balance"))
        #expect(!names.contains { $0.contains("suggest") || $0.contains("recommend") })
    }

    @Test("tools/call returns the report as readable text")
    func toolsCallReturnsContent() throws {
        let response = try #require(try ask(try makeServer(), request(
            "tools/call", ["name": "list_exercises", "arguments": ["muscle": "chest"]])))
        let content = try #require(response["result"]?["content"]?.arrayValue)
        let text = try #require(content.first?["text"]?.stringValue)

        #expect(content.first?["type"]?.stringValue == "text")
        #expect(text.contains("barbell-bench-press"))
        #expect(response["result"]?["isError"] != true)
    }

    @Test("A tool failure comes back as a tool result Claude can read and act on")
    func toolFailureIsAToolResult() throws {
        let response = try #require(try ask(try makeServer(snapshot: nil), request(
            "tools/call", ["name": "recent_sessions", "arguments": [:]])))

        #expect(response["result"]?["isError"] == true)
        #expect(response["error"] == nil, "a JSON-RPC error would hide this from the model")
        #expect(try #require(
            response["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue
        ).contains("snapshot.json"))
    }

    @Test("Calling a tool that does not exist names the ones that do")
    func unknownToolIsNamed() throws {
        let response = try #require(try ask(try makeServer(), request(
            "tools/call", ["name": "suggest_progression", "arguments": [:]])))

        #expect(response["result"]?["isError"] == true)
        #expect(try #require(
            response["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue
        ).contains("list_exercises"))
    }

    @Test("A call with no tool named is a protocol error, not a tool result")
    func missingToolNameIsAProtocolError() throws {
        let response = try #require(
            try ask(try makeServer(), request("tools/call", ["arguments": [:]])))

        #expect(response["error"]?["code"] == -32602)
    }

    // MARK: - The resource

    @Test("resources/list offers the context resource")
    func resourcesListOffersContext() throws {
        let resources = try #require(
            try ask(try makeServer(), request("resources/list"))?["result"]?["resources"]?
                .arrayValue)

        #expect(resources.contains { $0["uri"] == .string(MCPServer.contextResourceURI) })
        #expect(resources.first?["mimeType"]?.stringValue == "application/json")
    }

    @Test("resources/read hands back the context")
    func resourcesReadReturnsContext() throws {
        let response = try #require(try ask(try makeServer(), request(
            "resources/read", ["uri": .string(MCPServer.contextResourceURI)])))
        let contents = try #require(response["result"]?["contents"]?.arrayValue)

        #expect(contents.first?["uri"] == .string(MCPServer.contextResourceURI))
        #expect(try #require(contents.first?["text"]?.stringValue).contains("Autumn strength"))
    }

    @Test("Reading a resource this server does not have is an error, not empty text")
    func unknownResourceIsAnError() throws {
        let response = try #require(try ask(try makeServer(), request(
            "resources/read", ["uri": "liftingplan://nope"])))

        #expect(response["error"] != nil)
    }

    // MARK: - Protocol failures

    @Test("A line that is not JSON is a parse error rather than a crash")
    func malformedLineIsAParseError() throws {
        let line = try #require(try makeServer().handle(line: "{ nope"))
        let response = try JSONValue.parse(Data(line.utf8))

        #expect(response["error"]?["code"] == -32700)
        #expect(response["id"] == nil, "an id that was never readable is reported as null")
    }

    @Test("An unknown method is answered with the method-not-found code")
    func unknownMethodIsRejected() throws {
        let response = try #require(try ask(try makeServer(), request("sampling/createMessage")))

        #expect(response["error"]?["code"] == -32601)
    }

    @Test("A request with no method at all is an invalid request")
    func missingMethodIsInvalid() throws {
        let response = try #require(
            try ask(try makeServer(), ["jsonrpc": "2.0", "id": 7]))

        #expect(response["error"]?["code"] == -32600)
        #expect(response["id"] == 7)
    }
}
