import Foundation
import Testing
import LiftingKit
@testable import LiftingMCPKit

@Suite("Server configuration")
struct ServerConfigurationTests {

    private let home = URL(filePath: "/Users/user")

    private func resolve(
        _ arguments: [String] = ["lifting-mcp"], _ environment: [String: String] = [:]
    ) throws -> ServerConfiguration {
        try ServerConfiguration.resolve(
            arguments: arguments, environment: environment, home: home)
    }

    @Test("With nothing said, it is the app's own iCloud Documents folder")
    func defaultsToTheSharedFolder() throws {
        let configuration = try resolve()

        #expect(configuration.documentsDirectory.path(percentEncoded: false)
            == "/Users/user/Library/Mobile Documents/"
            + "iCloud~com~jonluongo~LiftingPlan/Documents")
        #expect(configuration.isDefaultLocation)
    }

    @Test("The default path is derived from the entitlement's container, not written out twice")
    func defaultPathIsDerived() {
        let path = ServerConfiguration.defaultDocumentsDirectory(home: home)
            .path(percentEncoded: false)

        #expect(path.contains(
            ServerConfiguration.containerIdentifier.replacingOccurrences(of: ".", with: "~")))
    }

    @Test("An environment variable repoints it, so a fixture folder can be used")
    func environmentRepoints() throws {
        let configuration = try resolve(["lifting-mcp"], ["LIFTINGPLAN_DOCUMENTS_DIR": "/tmp/fix"])

        #expect(configuration.documentsDirectory.path(percentEncoded: false) == "/tmp/fix")
        #expect(!configuration.isDefaultLocation)
    }

    @Test("An argument beats the environment, which beats the default")
    func argumentWins() throws {
        let configuration = try resolve(
            ["lifting-mcp", "--documents", "/tmp/argument"],
            ["LIFTINGPLAN_DOCUMENTS_DIR": "/tmp/environment"])

        #expect(configuration.documentsDirectory.path(percentEncoded: false) == "/tmp/argument")
    }

    @Test("An empty environment value is ignored rather than pointing at nowhere")
    func emptyEnvironmentIsIgnored() throws {
        #expect(try resolve(["lifting-mcp"], ["LIFTINGPLAN_DOCUMENTS_DIR": ""]).isDefaultLocation)
    }

    @Test("--documents with no path after it fails rather than quietly using iCloud")
    func flagWithoutValueFails() {
        #expect(throws: ConfigurationError.missingArgumentValue("--documents")) {
            try ServerConfiguration.resolve(
                arguments: ["lifting-mcp", "--documents"], environment: [:],
                home: URL(filePath: "/Users/user"))
        }
    }
}

@Suite("JSON values")
struct JSONValueTests {

    @Test("A whole number stays whole, so a set count does not read as a measurement")
    func integersStayIntegers() throws {
        #expect(try JSONValue.integer(3).lineEncoded() == "3")
    }

    @Test("Every JSON shape survives a round trip")
    func roundTrips() throws {
        let value: JSONValue = [
            "n": .null, "b": true, "i": 3, "d": 2.5, "s": "x", "a": [1, "two"],
            "o": ["nested": true],
        ]

        #expect(try JSONValue.parse(Data(value.lineEncoded().utf8)) == value)
    }

    @Test("A member explicitly sent as null reads the same as one that was omitted")
    func nullReadsAsAbsent() {
        let value: JSONValue = ["given": .null]

        #expect(value["given"] == nil)
        #expect(value["never"] == nil)
    }

    @Test("A line-encoded value never contains a newline, which would end it early")
    func linesAreSingleLines() throws {
        let value: JSONValue = ["text": "one\ntwo"]

        #expect(!(try value.lineEncoded().contains("\n")))
    }

    @Test("Dates are written the way both documents write them")
    func datesMatchTheDocuments() throws {
        let encoder = TrainingSnapshot.makeEncoder()
        encoder.outputFormatting = []
        let asDocument = String(decoding: try encoder.encode([referenceNow]), as: UTF8.self)

        #expect(asDocument == "[\(try JSONValue.date(referenceNow).lineEncoded())]")
    }
}
