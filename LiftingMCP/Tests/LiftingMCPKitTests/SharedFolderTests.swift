import Foundation
import Testing
import LiftingKit
@testable import LiftingMCPKit

/// The paths the in-memory fake deliberately does not exercise: a real folder
/// on disk, and the real 412-entry bundled catalog.
///
/// The Mac this runs on has no iCloud account, so the shared container does not
/// exist here — a temporary directory stands in for it. What that proves is
/// everything except iCloud's own syncing: the file names, the encoders, the
/// round trip, and that a plan this server writes is a plan the app can read.
@Suite("The shared folder")
struct SharedFolderTests {

    private func makeDirectory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A snapshot the app wrote is one the server reads")
    func readsWhatTheAppWrote() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = DocumentFolder(directory: directory)
        try folder.writeSnapshot(fixtureSnapshot())

        let outcome = try makeRunner(documents: folder)
            .call(ToolCatalog.recentSessions, arguments: [:])

        // The fixture holds one session with one performance against it.
        #expect(try #require(outcome.report)["sessionCount"] == 1)
    }

    @Test("A plan the server wrote lands on disk under the name the app reads")
    func writesWhatTheAppReads() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = DocumentFolder(directory: directory)

        let outcome = try makeRunner(documents: folder).call(
            ToolCatalog.writePlan,
            arguments: [
                "sessions": [[
                    "blockOrdinal": 1, "ordinal": 1, "focus": "Lower",
                    "entries": [[
                        "exerciseID": "barbell-squat", "restSeconds": 240,
                        "sets": .array(Array(
                            repeating: [
                                "target": "3",
                                "load": ["value": 315.0, "unit": "lb"],
                            ] as JSONValue,
                            count: 5)),
                    ]],
                ]],
            ])

        #expect(outcome.failureMessage == nil)
        // Read back through the app's own side of the transport, so this is the
        // real decode the phone performs and not a second one written here.
        let read = try #require(try folder.readPlan())
        let session = try #require(read.sessions.first)
        #expect(session.blockOrdinal == 1)
        #expect(session.focus == "Lower")
        let exercise = try #require(session.exercises.first)
        #expect(exercise.sets.count == 5)
        #expect(exercise.sets.first?.load == Mass(value: 315, unit: .pounds))
    }

    @Test("A folder that does not exist reads as no snapshot rather than as an error")
    func absentFolderReadsAsNoSnapshot() throws {
        let folder = DocumentFolder(
            directory: URL.temporaryDirectory.appending(path: UUID().uuidString))

        let message = try #require(
            try makeRunner(documents: folder)
                .call(ToolCatalog.recentSessions, arguments: [:]).failureMessage)

        #expect(message.contains("No training snapshot yet"))
        #expect(message.contains("snapshot.json"))
    }

    @Test("A snapshot that is there but malformed is a different failure from an absent one")
    func malformedSnapshotIsNotAbsence() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{ not a snapshot".utf8)
            .write(to: directory.appending(path: DocumentFolder.snapshotFilename))

        let message = try #require(
            try makeRunner(documents: DocumentFolder(directory: directory))
                .call(ToolCatalog.recentSessions, arguments: [:]).failureMessage)

        #expect(message.contains("could not be read"))
    }

    @Test("The folder names itself in an error, so the owner is not left guessing")
    func folderNamesItself() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = DocumentFolder(directory: directory)

        #expect(folder.snapshotLocation.hasSuffix("/snapshot.json"))
        #expect(folder.planLocation.hasSuffix("/plan.json"))
    }
}

/// The real catalog, not a fixture. If a resource fails to resolve it does not
/// look like an error — it looks like a lifter with nothing to choose from —
/// so this asserts the bundled data actually reaches the server.
@Suite("The bundled catalog")
struct BundledCatalogTests {

    private func runner() throws -> ToolRunner {
        try makeRunner(
            documents: InMemoryDocuments(snapshot: fixtureSnapshot()),
            catalog: try ExerciseCatalog.bundled())
    }

    @Test("The server reaches the real catalog through the package's own bundle")
    func realCatalogLoads() throws {
        let catalog = try ExerciseCatalog.bundled()

        #expect(catalog.version == 5)
        #expect(catalog.all.count == 412)
    }

    @Test("list_exercises answers from the real catalog with real IDs")
    func listsRealExercises() throws {
        let outcome = try runner().call(
            ToolCatalog.listExercises, arguments: ["muscle": "chest", "equipment": "barbell"])
        let report = try #require(outcome.report)
        let entries = try #require(report["exercises"]?.arrayValue)

        #expect(!entries.isEmpty)
        #expect(entries.contains { $0["id"] == "barbell-bench-press" })
        #expect(entries.allSatisfy { $0["equipment"] == "barbell" })
        #expect(entries.allSatisfy { $0["primaryMuscles"]?.arrayValue?.contains("chest") == true })
    }

    @Test("Every ID list_exercises reports is one write_plan accepts")
    func reportedIDsAreAcceptedIDs() throws {
        let runner = try runner()
        let report = try #require(
            runner.call(ToolCatalog.listExercises, arguments: ["pattern": "squat"]).report)
        let ids = try #require(report["exercises"]?.arrayValue)
            .compactMap { $0["id"]?.stringValue }

        #expect(!ids.isEmpty)
        let outcome = runner.call(
            ToolCatalog.writePlan,
            arguments: [
                // Block 2: the fixture has a performance against block 1
                // session 1, and rewriting a session he has trained is refused —
                // which is the rule working, not the test being awkward.
                "sessions": [[
                    "blockOrdinal": 2, "ordinal": 1,
                    "entries": .array(
                        ids.map {
                            [
                                "exerciseID": .string($0),
                                "sets": [["target": "5"]],
                            ]
                        }),
                ]]
            ])

        #expect(outcome.failureMessage == nil)
    }
}
