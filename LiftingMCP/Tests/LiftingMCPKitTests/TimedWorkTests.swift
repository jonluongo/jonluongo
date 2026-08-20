import Foundation
import Testing
import LiftingKit
@testable import LiftingMCPKit

/// Work held for time, from the plan Claude writes to the volume report he
/// reads back.
///
/// The whole point is that a number counted in seconds never turns up anywhere
/// as a number of repetitions. Each test here stands at one of the places it
/// used to.
@Suite("Timed work through the server")
struct TimedWorkTests {

    private static let plank = ExerciseID(rawValue: "push-up")

    /// A block whose only movement is held for time: three sets of a
    /// thirty-second hold, two of them logged — one at 34 seconds and one at 28.
    private func heldSnapshot() -> TrainingSnapshot {
        let block = fixtureRoutine(
            title: "Hold block", goal: "Trunk", startDate: daysAgo(10),
            blocks: [(label: nil, isDeload: false, days: [
                fixtureDay(
                    weekday: .monday, focus: "Trunk", completedAt: daysAgo(2),
                    exercises: [
                        FixtureExercise(
                            exercise: PlanDocumentExercise(
                                exerciseID: Self.plank, displayName: "Push Up", sets: 3,
                                repRange: "30 seconds", restSeconds: 60),
                            logged: [
                                set(0, nil, 0, at: daysAgo(2), durationSeconds: 34),
                                set(1, nil, 0, at: daysAgo(2), durationSeconds: 28),
                            ])
                    ])
            ])])
        return fixtureSnapshot(blocks: [block])
    }

    private func report(_ tool: String, _ arguments: JSONValue = [:]) throws -> JSONValue {
        let outcome = try makeRunner(documents: InMemoryDocuments(snapshot: heldSnapshot()))
            .call(tool, arguments: arguments)
        return try #require(outcome.report)
    }

    // MARK: - A hold is never a repetition

    @Test("A held set adds seconds to the volume report and no reps at all")
    func volumeCountsSecondsNotReps() throws {
        let muscles = try #require(try report(ToolCatalog.volumeByMuscle)["muscles"]?.arrayValue)
        let chest = try #require(muscles.first { $0["muscle"] == "chest" })

        #expect(chest["primarySets"] == 2)
        #expect(chest["primarySeconds"] == 62, "34 and 28 seconds were held")
        #expect(chest["primaryReps"] == 0, "not one repetition was performed")
    }

    @Test("Secondary muscles are reported in seconds too, and not in reps")
    func secondaryVolumeCountsSeconds() throws {
        let muscles = try #require(try report(ToolCatalog.volumeByMuscle)["muscles"]?.arrayValue)
        let triceps = try #require(muscles.first { $0["muscle"] == "triceps" })

        #expect(triceps["secondarySets"] == 2)
        #expect(triceps["secondarySeconds"] == 62)
        #expect(triceps["secondaryReps"] == 0)
    }

    @Test("The volume report says in words that seconds are not reps")
    func volumeSaysWhatItCounts() throws {
        let counts = try #require(try report(ToolCatalog.volumeByMuscle)["counts"]?.stringValue)
        #expect(counts.contains("seconds"))
    }

    @Test("A held set reports its duration in the history, with no reps beside it")
    func historyReportsDuration() throws {
        let sets = try #require(
            try report(ToolCatalog.exerciseHistory, ["id": "push-up"])["sets"]?.arrayValue)

        #expect(sets.count == 2)
        #expect(sets.first?["durationSeconds"] == 34)
        #expect(sets.first?["reps"] == 0)
        #expect(sets.first?["prescribed"]?["repRange"] == "30 seconds")
    }

    @Test("A session reports the seconds each set was held")
    func sessionsReportDuration() throws {
        let sessions = try #require(
            try report(ToolCatalog.recentSessions)["sessions"]?.arrayValue)
        let exercises = try #require(sessions.first?["exercises"]?.arrayValue)
        let sets = try #require(exercises.first?["sets"]?.arrayValue)

        #expect(sets.map { $0["durationSeconds"] } == [34, 28])
        #expect(sets.map { $0["reps"] } == [0, 0])
    }

    @Test("A counted set reports no duration rather than a zero one")
    func countedSetReportsNoDuration() throws {
        let outcome = try makeRunner(documents: InMemoryDocuments(snapshot: fixtureSnapshot()))
            .call(ToolCatalog.exerciseHistory, arguments: ["id": "barbell-bench-press"])
        let report = try #require(outcome.report)
        let sets = try #require(report["sets"]?.arrayValue)

        // Read through `objectValue`: the subscript answers `nil` for an
        // explicit null as readily as for an absent key, and the claim here is
        // that the key is present and null rather than missing.
        #expect(sets.allSatisfy { $0.objectValue?["durationSeconds"] == .null })
        #expect(sets.contains { ($0["reps"]?.intValue ?? 0) > 0 })
    }

    // MARK: - Claude can learn all of this before he calls

    /// The value at a path through an advertised schema, the way a client
    /// reading `tools/list` would walk it.
    private func value(at path: [String], in schema: JSONValue) throws -> JSONValue {
        var current = schema
        for key in path {
            let step = Int(key).flatMap { current[$0] } ?? current[key]
            current = try #require(step, "nothing at '\(key)' in \(path.joined(separator: "."))")
        }
        return current
    }

    @Test("write_plan says how a hold is written and how it is logged")
    func writePlanSchemaSaysSo() throws {
        let definition = ToolCatalog.writePlanDefinition
        let target = try value(
            at: [
                "properties", "blocks", "items", "properties", "days", "items",
                // An entry of a day is an exercise or a group, so the exercise
                // shape is the first of the two the item may take.
                "properties", "exercises", "items", "anyOf", "0",
                "properties", "repRange", "description",
            ],
            in: definition.inputSchema)
        let described = try #require(target.stringValue)

        #expect(described.contains("30 seconds"))
        #expect(described.contains("seconds rather than reps"))
        // The tool's own description, not only the field's: a caller skimming
        // the tool list must be able to see it without opening the schema.
        #expect(definition.description.contains("held for time"))
    }

    @Test("The reporting tools say that seconds and reps are reported apart")
    func reportingSchemasSaySo() throws {
        #expect(ToolCatalog.volumeByMuscleDefinition.description.contains("seconds"))
        #expect(ToolCatalog.exerciseHistoryDefinition.description.contains("durationSeconds"))
        #expect(ToolCatalog.recentSessionsDefinition.description.contains("durationSeconds"))
    }

    // MARK: - A timed plan survives the trip to the phone as bytes

    @Test("A plan prescribing a hold is written to the folder and reads back intact")
    func timedPlanSurvivesTheFile() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "timed-plan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let documents = DocumentFolder(directory: folder)
        let outcome = try makeRunner(documents: documents).call(
            ToolCatalog.writePlan,
            arguments: [
                "title": "Hold block",
                "blocks": [["days": [[
                    "weekday": "monday",
                    "exercises": [[
                        "exerciseID": "push-up", "displayName": "Push Up",
                        "sets": [["repRange": "30 seconds"], ["repRange": "45 seconds"]],
                    ]],
                ]]]],
            ])
        #expect(outcome.failureMessage == nil)

        // Read back through the phone's own decoder, from the bytes on disk —
        // the one direction an encode-then-decode round trip cannot vouch for.
        let read = try #require(try documents.readPlan())
        let exercise = try #require(read.blocks.first?.days.first?.exercises.first)

        #expect(exercise.prescribedSets.map(\.repRange) == ["30 seconds", "45 seconds"])
        #expect(RepRange(exercise.repRange).isEmpty, "a hold states no rep count")
        #expect(WorkDuration("30 seconds").seconds == 30)
    }
}
