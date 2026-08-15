import Foundation
import Testing
import LiftingKit
@testable import LiftingMCPKit

/// The owner's actual first experience. The app has never backgrounded on a
/// device, so `snapshot.json` is not there — and every tool has to say so in a
/// way he can act on, rather than crash or answer with an empty report that
/// looks exactly like a lifter with no history.
@Suite("No snapshot yet")
struct MissingSnapshotTests {

    private static let readingTools = [
        ToolCatalog.listExercises, ToolCatalog.exerciseHistory,
        ToolCatalog.recentSessions, ToolCatalog.volumeByMuscle,
    ]

    @Test("Every reading tool fails rather than reporting an empty result",
          arguments: readingTools)
    func toolsFailWhenNoSnapshot(tool: String) throws {
        let runner = try makeRunner(documents: InMemoryDocuments())

        let outcome = runner.call(tool, arguments: ["id": "barbell-bench-press"])

        #expect(outcome.report == nil, "an empty report would read as a lifter with no history")
        #expect(outcome.failureMessage != nil)
    }

    @Test("The context resource fails the same way rather than describing nobody")
    func contextFailsWhenNoSnapshot() throws {
        let runner = try makeRunner(documents: InMemoryDocuments())

        #expect(runner.contextResource().report == nil)
    }

    @Test("The message names the file, the one action that creates it, and where it looked")
    func messageIsActionable() throws {
        let documents = InMemoryDocuments()
        let runner = try makeRunner(documents: documents)

        let message = try #require(
            runner.call(ToolCatalog.recentSessions, arguments: [:]).failureMessage)

        #expect(message.contains("snapshot.json"))
        #expect(message.contains("background"))
        #expect(message.contains(documents.snapshotLocation))
        #expect(message.contains(ServerConfiguration.directoryEnvironmentKey))
    }

    @Test("A snapshot that is there but unreadable is told apart from one that is absent")
    func brokenTransportIsNotAbsence() throws {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot())
        documents.breakTransport()
        let runner = try makeRunner(documents: documents)

        let message = try #require(
            runner.call(ToolCatalog.recentSessions, arguments: [:]).failureMessage)

        #expect(message.contains("could not be read"))
        #expect(!message.contains("No training snapshot yet"))
    }

    @Test("write_plan does not need a snapshot — a lifter with no history still gets a plan")
    func writePlanWorksWithoutSnapshot() throws {
        let documents = InMemoryDocuments()
        let runner = try makeRunner(documents: documents)

        let outcome = runner.call(
            ToolCatalog.writePlan,
            arguments: [
                "title": "First block",
                "days": [[
                    "weekday": "monday",
                    "exercises": [[
                        "exerciseID": "barbell-squat", "displayName": "Barbell Squat", "sets": 3,
                    ]],
                ]],
            ])

        #expect(outcome.failureMessage == nil)
        #expect(documents.lastWrittenPlan?.title == "First block")
    }
}
