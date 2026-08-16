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

        #expect(try #require(outcome.report)["totalSessions"] == 3)
    }

    @Test("A plan the server wrote lands on disk under the name the app reads")
    func writesWhatTheAppReads() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = DocumentFolder(directory: directory)

        let outcome = try makeRunner(documents: folder).call(
            ToolCatalog.writePlan,
            arguments: [
                "title": "Autumn strength",
                "days": [[
                    "weekday": "monday",
                    "exercises": [[
                        "exerciseID": "barbell-squat", "displayName": "Barbell Squat",
                        "sets": 5, "repRange": "3", "restSeconds": 240,
                        "suggestedLoad": ["value": 315.0, "unit": "lb"],
                    ]],
                ]],
            ])

        #expect(outcome.failureMessage == nil)
        // Read back through the app's own side of the transport, so this is the
        // real decode the phone performs and not a second one written here.
        let read = try #require(try folder.readPlan())
        #expect(read.title == "Autumn strength")
        #expect(read.everyDay.first?.weekday == .monday)
        #expect(read.everyDay.first?.exercises.first?.sets == 5)
        #expect(read.everyDay.first?.exercises.first?.suggestedLoad
            == Mass(value: 315, unit: .pounds))
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
                "days": [[
                    "weekday": "monday",
                    "exercises": .array(
                        ids.map {
                            ["exerciseID": .string($0), "displayName": .string($0), "sets": 3]
                        }),
                ]]
            ])

        #expect(outcome.failureMessage == nil)
    }
}
