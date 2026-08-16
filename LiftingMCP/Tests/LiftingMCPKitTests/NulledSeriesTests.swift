import Foundation
import Testing
import LiftingKit

@testable import LiftingMCPKit

/// A `null` on a dated series, answered by both clients at once.
///
/// The two used to disagree: `ProfileUpdate`'s decoder refused it with a reason
/// while this server's argument reader accepted and ignored it, so a caller was
/// told the write had succeeded and that the fact was "left as it was" — and
/// then told by the phone, had the same document ever been written by hand,
/// that it could not be read at all. CLAUDE.md binds this: the rule lives in
/// `DocumentRefusal` so the phone and the Mac cannot answer it differently.
/// These tests assert the same sentence comes out of both.
@Suite("A nulled series is refused by both clients")
struct NulledSeriesTests {

    private func update(_ arguments: JSONValue) throws -> ToolOutcome {
        try makeRunner(documents: InMemoryDocuments(snapshot: fixtureSnapshot()))
            .call(ToolCatalog.updateProfile, arguments: arguments)
    }

    /// What the phone says when it decodes a document stating the same thing.
    private func documentRefusal(for key: String) -> String? {
        let json = """
            {"version": 3, "id": "\(UUID().uuidString)",
             "generatedAt": "2026-08-15T12:00:00Z", "goal": "strength", "\(key)": null}
            """
        do {
            _ = try ProfileUpdate.makeDecoder()
                .decode(ProfileUpdate.self, from: Data(json.utf8))
            return nil
        } catch {
            return (error as? DocumentRefusal)?.message
        }
    }

    @Test("A null bodyweight is refused by the tool, not accepted and ignored")
    func nullBodyweightIsRefused() throws {
        let outcome = try update(["goal": "strength", "bodyweight": .null])
        let message = try #require(
            outcome.failureMessage, "a null series used to report success")

        #expect(message.contains("'bodyweight' is a dated series"))
        #expect(message.contains("state that day's reading again"))
    }

    @Test("A null baselines is refused by the tool for the same reason")
    func nullBaselinesIsRefused() throws {
        let outcome = try update(["goal": "strength", "baselines": .null])
        let message = try #require(outcome.failureMessage)

        #expect(message.contains("'baselines' is a dated series"))
        #expect(message.contains("state that lift's baseline again"))
    }

    @Test("The tool and the document give the same answer, word for word",
          arguments: ["bodyweight", "baselines"])
    func bothClientsSayTheSameThing(key: String) throws {
        let fromTool = try #require(
            try update(["goal": "strength", .init(key): .null]).failureMessage)
        let fromDocument = try #require(documentRefusal(for: key))

        #expect(fromTool == fromDocument)
    }

    @Test("Nothing at all is written when a series is nulled")
    func nothingIsWritten() throws {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot())
        _ = try makeRunner(documents: documents).call(
            ToolCatalog.updateProfile,
            arguments: ["goal": "strength", "bodyweight": .null])

        #expect(
            documents.lastWrittenProfileUpdate == nil,
            "a refused call must not write the rest of itself")
    }

    @Test("A single fact can still be returned to not-known with a null")
    func singleFactsStillAcceptNull() throws {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot())
        let outcome = try makeRunner(documents: documents)
            .call(ToolCatalog.updateProfile, arguments: ["equipment": .null])
        let written = try #require(documents.lastWrittenProfileUpdate)

        #expect(outcome.failureMessage == nil)
        #expect(written.equipment == .unstated)
    }

    @Test("A stated series is unaffected by the guard")
    func statedSeriesStillRecorded() throws {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot())
        let outcome = try makeRunner(documents: documents).call(
            ToolCatalog.updateProfile,
            arguments: ["bodyweight": ["value": 182, "unit": "lb"]])
        let written = try #require(documents.lastWrittenProfileUpdate)

        #expect(outcome.failureMessage == nil)
        #expect(written.bodyweight.count == 1)
    }

    @Test("The tool's description tells a caller the exception before he calls")
    func schemaSaysSo() {
        let described = ToolCatalog.updateProfileDefinition.description

        #expect(described.contains("cannot be nulled"))
        #expect(described.contains("refused rather than ignored"))
    }
}
