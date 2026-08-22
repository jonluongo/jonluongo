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

    /// The context resource as the coach receives it.
    private func contextText(of server: MCPServer) throws -> String {
        let params: JSONValue = ["uri": .string(MCPServer.contextResourceURI)]
        let answer = try ask(server, request("resources/read", params))
        let contents = try #require(answer?["result"]?["contents"]?.arrayValue)
        return try #require(contents.first?["text"]?.stringValue)
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

    @Test("tools/list advertises exactly the six tools, each with a schema")
    func toolsListIsComplete() throws {
        let tools = try #require(
            try ask(try makeServer(), request("tools/list"))?["result"]?["tools"]?.arrayValue)
        let names = tools.compactMap { $0["name"]?.stringValue }.sorted()

        // `update_profile` and `unstated_facts` went with the profile: who he
        // is is prose in ACCOUNT.md, edited with `update_notes`.
        #expect(names == [
            "exercise_history", "list_exercises", "recent_sessions",
            "update_notes", "volume_by_muscle", "write_plan",
        ])
        #expect(tools.allSatisfy { $0["inputSchema"]?["type"]?.stringValue == "object" })
        #expect(tools.allSatisfy { $0["description"]?.stringValue?.isEmpty == false })
    }

    @Test("A plan the phone refused is the first thing the context says")
    func aRefusalReachesTheCoach() throws {
        // **The coach is absent at the checkpoint that catches this.**
        // `write_plan` refuses a format error while he is still there; the phone
        // refuses a plan rewriting a session already trained, long after the
        // server answered *written*. Before this, that refusal reached an alert
        // on a phone he cannot see and stopped there — and he went on
        // prescribing against a block that had never landed.
        let refusal = SnapshotRefusal(
            at: daysAgo(1),
            reason: "This plan changes session 2 of block 3, which has already been trained.")
        let server = MCPServer(
            runner: try makeRunner(
                documents: InMemoryDocuments(snapshot: fixtureSnapshot(refused: refusal))))

        let text = try contextText(of: server)

        #expect(text.contains("planRefused"))
        #expect(text.contains("already been trained"))
        #expect(text.contains("took none of it in"), "and what that means for the record below")
    }

    @Test("A record with nothing refused says nothing about refusals")
    func silenceWhenThereIsNothingToSay() throws {
        let text = try contextText(of: try makeServer())

        #expect(!text.contains("planRefused"), "an empty key is a question he has to answer")
    }

    @Test("The published schema does not promise a shape the decoder refuses")
    func theSchemaAgreesWithTheDecoder() throws {
        // **A coach can only send what the schema says.** `load.value` was
        // declared a string beside `intensity.value`, which really is one — two
        // adjacent fields of the same name, identically written, decoding
        // differently. `Mass.value` is a `Double`, so a coach who followed the
        // published schema and sent "185" was told his load had the wrong type,
        // every time, with nothing in the message pointing at the schema as the
        // thing that was wrong.
        //
        // Asserted as agreement rather than as a literal: the declared type is
        // read out of the schema and then actually decoded.
        let tools = try #require(
            try ask(try makeServer(), request("tools/list"))?["result"]?["tools"]?.arrayValue)
        let writePlan = try #require(tools.first { $0["name"]?.stringValue == "write_plan" })
        func properties(of schema: JSONValue) throws -> JSONValue {
            try #require(schema["properties"])
        }
        func items(_ schema: JSONValue, _ key: String) throws -> JSONValue {
            try #require(try properties(of: schema)[key]?["items"])
        }
        let session = try items(try #require(writePlan["inputSchema"]), "sessions")
        let entry = try items(session, "entries")
        let set = try properties(of: try items(entry, "sets"))

        #expect(set["load"]?["properties"]?["value"]?["type"]?.stringValue == "number")
        #expect(set["intensity"]?["properties"]?["value"]?["type"]?.stringValue == "string")

        // And a document written that way is one the decoder takes.
        let json = """
        {
          "version": 6, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "sessions": [{"blockOrdinal": 1, "ordinal": 1, "entries": [
            {"exerciseID": "dumbbell-fly", "sets": [
              {"load": {"value": 62.5, "unit": "kg"},
               "intensity": {"scale": "rpe", "value": "8-9"}}
            ]}
          ]}]
        }
        """
        let plan = try PlanDocument.makeDecoder().decode(
            PlanDocument.self, from: try #require(json.data(using: .utf8)))
        #expect(plan.sessions.first?.exercises.first?.sets.first?.load?.value == 62.5)
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
        // **The record's own date leads it.** A coach reading a summary needs to
        // know when it was written before he believes any of it — that is the
        // failure this whole resource is shaped around.
        #expect(try #require(contents.first?["text"]?.stringValue).contains("exportedAt"))
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

/// How the connector introduces itself.
///
/// **A client draws this before any tool runs**, so it is the one thing a reader
/// sees whether or not the loop is working — and it was announcing itself as
/// `liftingplan`, the Xcode project's name, which is neither the product's name
/// nor anything a reader would recognise in a list of connectors.
@Suite("The connector's identity")
struct ServerIdentityTests {

    @Test("It answers with the product's name, its title, and its mark")
    func identityIsComplete() throws {
        let info = MCPServer.serverInfo
        guard case .object(let fields) = info else {
            Issue.record("serverInfo is not an object"); return
        }
        #expect(fields["name"] == .string("Superset"))
        #expect(fields["title"] != nil, "a title is what a human reads")
        #expect(fields["version"] != nil)
    }

    @Test("The mark is a self-contained PNG, not a link")
    func theMarkTravelsWithIt() throws {
        // A connector that fetches its own icon shows nothing when the network
        // is not there — and this one runs beside a loop whose whole problem
        // has been things not arriving.
        guard case .object(let fields) = MCPServer.serverInfo,
            case .array(let icons)? = fields["icons"],
            case .object(let first)? = icons.first,
            case .string(let src)? = first["src"]
        else { Issue.record("no icon in serverInfo"); return }

        #expect(src.hasPrefix("data:image/png;base64,"))
        #expect(first["mimeType"] == .string("image/png"))

        let encoded = String(src.dropFirst("data:image/png;base64,".count))
        let bytes = try #require(Data(base64Encoded: encoded))
        #expect(bytes.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]), "a real PNG")
        #expect(bytes.count > 1000, "not an empty placeholder")
    }
}
