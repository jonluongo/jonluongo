import Foundation
import Testing
import LiftingKit
@testable import LiftingMCPKit

/// Work carried over a distance, from the plan Claude writes to the volume
/// report he reads back.
///
/// The gap these close is the one the last review named and left open: a
/// farmer's carry prescribed as `"40 metres"` travelled and displayed correctly,
/// and there was nowhere to log how far he went. The whole point of the fix is
/// that metres never turn up anywhere as repetitions or as seconds — the same
/// failure timed work had, in a third unit.
@Suite("Carried work through the server")
struct CarriedWorkTests {

    private static let carry = ExerciseID(rawValue: "kettlebell-farmers-carry")
    private static let sled = ExerciseID(rawValue: "sled-push")

    /// The two real carry entries, decoded from the shapes `exercises.json`
    /// actually holds. A catalog of its own rather than an addition to the
    /// shared fixture, which other suites count the entries of.
    private func carryCatalog() throws -> ExerciseCatalog {
        let json = """
            [
              {"id": "kettlebell-farmers-carry", "displayName": "Kettlebell Farmers Carry",
               "primaryMuscles": ["abdominals"], "secondaryMuscles": ["forearms", "traps"],
               "equipment": "kettlebell", "pattern": "carry", "force": "static",
               "mechanic": "compound", "category": "strength", "difficulty": "intermediate"},
              {"id": "sled-push", "displayName": "Sled Push",
               "primaryMuscles": ["quadriceps"],
               "secondaryMuscles": ["calves", "chest", "glutes", "hamstrings", "triceps"],
               "equipment": "sled", "pattern": "carry", "force": "push",
               "mechanic": "compound", "category": "strength", "difficulty": "intermediate"}
            ]
            """
        let exercises = try JSONDecoder().decode([Exercise].self, from: Data(json.utf8))
        return ExerciseCatalog(exercises: exercises, version: 5)
    }

    /// One carry prescribed over a distance, with the sets logged against it.
    private func carried(
        _ id: ExerciseID, target: String, name: String, sets: [FixtureSet]
    ) -> FixtureExercise {
        FixtureExercise(
            exercise: PlanDocumentExercise(
                exerciseID: id, displayName: name, sets: sets.count, repRange: target,
                restSeconds: 90, suggestedLoad: Mass(value: 32, unit: .kilograms)),
            logged: sets)
    }

    private func loggedCarry(_ index: Int, _ distance: Distance?) -> FixtureSet {
        set(index, 32 * 2.20462, 0, at: daysAgo(2), distance: distance)
    }

    /// A block of carries: two farmer's carries in metres, one sled push in
    /// yards. Two units on purpose — nothing may add them together.
    private func carriedSnapshot() -> TrainingSnapshot {
        let block = fixtureRoutine(
            title: "Carry block", goal: "Grip", startDate: daysAgo(10),
            blocks: [(label: nil, isDeload: false, days: [
                fixtureDay(
                    weekday: .monday, focus: "Carries", completedAt: daysAgo(2),
                    exercises: [
                        carried(
                            Self.carry, target: "40 metres", name: "Kettlebell Farmers Carry",
                            sets: [
                                loggedCarry(0, Distance(value: 40, unit: .metres)),
                                loggedCarry(1, Distance(value: 38, unit: .metres)),
                            ]),
                        carried(
                            Self.sled, target: "20 yards", name: "Sled Push",
                            sets: [loggedCarry(0, Distance(value: 20, unit: .yards))]),
                    ])
            ])])
        return fixtureSnapshot(blocks: [block])
    }

    /// The context resource over the carry block, read the same way the coach
    /// receives it.
    private func context() throws -> JSONValue {
        try #require(
            try makeRunner(
                documents: InMemoryDocuments(snapshot: carriedSnapshot()),
                catalog: try carryCatalog()
            ).contextResource().report)
    }

    private func report(_ tool: String, _ arguments: JSONValue = [:]) throws -> JSONValue {
        let outcome = try makeRunner(
            documents: InMemoryDocuments(snapshot: carriedSnapshot()),
            catalog: try carryCatalog()
        ).call(tool, arguments: arguments)
        return try #require(outcome.report)
    }

    // MARK: - A metre is never a repetition and never a second

    @Test("A carried set adds distance to the volume report and no reps or seconds at all")
    func volumeCountsDistanceNotReps() throws {
        let muscles = try #require(try report(ToolCatalog.volumeByMuscle)["muscles"]?.arrayValue)
        let abdominals = try #require(muscles.first { $0["muscle"] == "abdominals" })

        #expect(abdominals["primarySets"] == 2)
        #expect(abdominals["primaryReps"] == 0, "not one repetition was performed")
        #expect(abdominals["primarySeconds"] == 0, "nothing was held")
        #expect(
            abdominals["primaryDistance"]?.arrayValue
                == [["unit": "m", "value": 78.0]], "40 metres and 38 metres")
    }

    @Test("Secondary muscles carry the same distance, and still no reps")
    func secondaryVolumeCountsDistance() throws {
        let muscles = try #require(try report(ToolCatalog.volumeByMuscle)["muscles"]?.arrayValue)
        let forearms = try #require(muscles.first { $0["muscle"] == "forearms" })

        #expect(forearms["secondarySets"] == 2)
        #expect(forearms["secondaryReps"] == 0)
        #expect(forearms["secondaryDistance"]?.arrayValue == [["unit": "m", "value": 78.0]])
    }

    @Test("Two units are reported side by side and never added together")
    func unitsAreNeverSummed() throws {
        let muscles = try #require(try report(ToolCatalog.volumeByMuscle)["muscles"]?.arrayValue)
        let quadriceps = try #require(muscles.first { $0["muscle"] == "quadriceps" })

        #expect(quadriceps["primaryDistance"]?.arrayValue == [["unit": "yd", "value": 20.0]])
        let carried = try #require(muscles.first { $0["muscle"] == "abdominals" })
        #expect(carried["primaryDistance"]?.arrayValue == [["unit": "m", "value": 78.0]])
    }

    @Test("A muscle nothing was carried for reports an empty distance, not a zero one")
    func nothingCarriedReportsNoDistance() throws {
        let outcome = try makeRunner(documents: InMemoryDocuments(snapshot: fixtureSnapshot()))
            .call(ToolCatalog.volumeByMuscle, arguments: [:])
        let report = try #require(outcome.report)
        let muscles = try #require(report["muscles"]?.arrayValue)

        #expect(muscles.allSatisfy { $0["primaryDistance"]?.arrayValue == [] })
    }

    @Test("The volume report says in words that distance is counted apart")
    func volumeSaysWhatItCounts() throws {
        let counts = try #require(try report(ToolCatalog.volumeByMuscle)["counts"]?.stringValue)

        #expect(counts.contains("distance"))
    }

    // MARK: - What he is working with

    /// The context resource is the one report the coach reads on every turn,
    /// and it spoke in loads and repetitions only. A carry has neither: it
    /// reported `"reps": 0` for a lifter who walked 38 metres under two 32 kg
    /// bells — a number nobody performed, in the summary that shapes what is
    /// prescribed next.
    @Test("A carry is stated as a distance in the working weights, never as zero reps")
    func workingWeightsStateTheCarry() throws {
        let weights = try #require(try context()["workingWeights"]?.arrayValue)
        let carry = try #require(
            weights.first { $0["exerciseID"] == "kettlebell-farmers-carry" })

        #expect(carry["distance"] == ["value": 38.0, "unit": "m"], "the last one he carried")
        #expect(carry.objectValue?["durationSeconds"] == .null, "nothing was held")
        // Zero here is the record's own spelling for a set that was not counted
        // — `LoggedSetRecord.reps` is not optional — and it is only honest
        // because the distance stands beside it saying which measure was
        // performed. Alone, as it was, it read as a carry that went nowhere.
        #expect(carry["reps"] == 0)
    }

    /// Its pair: a counted lift still reports the reps it was counted in, and
    /// says nothing about seconds or metres.
    @Test("A counted lift still states its reps, and no distance beside them")
    func workingWeightsStateCountedReps() throws {
        let counted = try #require(
            try makeRunner(documents: InMemoryDocuments(snapshot: fixtureSnapshot()))
                .contextResource().report)
        let weights = try #require(counted["workingWeights"]?.arrayValue)
        let bench = try #require(weights.first { $0["exerciseID"] == "barbell-bench-press" })

        #expect(bench["reps"] != .null)
        #expect(bench.objectValue?["distance"] == .null)
        #expect(bench.objectValue?["durationSeconds"] == .null)
    }

    // MARK: - What the log reports back

    @Test("A carried set reports its distance in the history, with no reps beside it")
    func historyReportsDistance() throws {
        let sets = try #require(
            try report(
                ToolCatalog.exerciseHistory, ["id": "kettlebell-farmers-carry"]
            )["sets"]?.arrayValue)

        #expect(sets.count == 2)
        #expect(sets.first?["distance"] == ["value": 40.0, "unit": "m"])
        #expect(sets.first?["reps"] == 0)
        #expect(sets.first?["durationSeconds"] == nil)
        #expect(sets.first?["prescribed"]?["repRange"] == "40 metres")
    }

    @Test("A counted set reports no distance rather than a zero one")
    func countedSetReportsNoDistance() throws {
        let outcome = try makeRunner(documents: InMemoryDocuments(snapshot: fixtureSnapshot()))
            .call(ToolCatalog.exerciseHistory, arguments: ["id": "barbell-bench-press"])
        let report = try #require(outcome.report)
        let sets = try #require(report["sets"]?.arrayValue)

        // Read through `objectValue`: the subscript answers `nil` for an
        // explicit null as readily as for an absent key, and the claim here is
        // that the key is present and null rather than missing.
        #expect(sets.allSatisfy { $0.objectValue?["distance"] == .null })
    }

    @Test("A session reports how far each set was carried")
    func sessionsReportDistance() throws {
        let sessions = try #require(try report(ToolCatalog.recentSessions)["sessions"]?.arrayValue)
        let exercises = try #require(sessions.first?["exercises"]?.arrayValue)
        let sets = try #require(exercises.first?["sets"]?.arrayValue)

        #expect(sets.map { $0["distance"] } == [["value": 40.0, "unit": "m"], ["value": 38.0, "unit": "m"]])
        #expect(sets.map { $0["reps"] } == [0, 0])
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

    private func repRangeDescription() throws -> String {
        let described = try value(
            at: [
                "properties", "blocks", "items", "properties", "days", "items",
                // An entry of a day is an exercise or a group, so the exercise
                // shape is the first of the two the item may take.
                "properties", "exercises", "items", "anyOf", "0",
                "properties", "repRange", "description",
            ],
            in: ToolCatalog.writePlanDefinition.inputSchema)
        return try #require(described.stringValue)
    }

    @Test("write_plan says how a carry is written and how it is logged")
    func writePlanSchemaSaysSo() throws {
        let described = try repRangeDescription()

        #expect(described.contains("40 m"))
        #expect(described.contains("distance"))
        #expect(ToolCatalog.writePlanDefinition.description.contains("carried"))
    }

    @Test("write_plan no longer claims a distance cannot be recorded")
    func writePlanNoLongerSaysItCannotBeLogged() throws {
        let described = try repRangeDescription()

        #expect(!described.contains("nowhere to record"))
        #expect(!described.contains("only reps and seconds can be logged"))
    }

    @Test("write_plan names the units a distance can be logged in")
    func writePlanNamesTheUnits() throws {
        let described = try repRangeDescription()

        #expect(DistanceUnit.known.allSatisfy { described.contains($0.rawValue) })
    }

    @Test("The reporting tools say that distance is reported apart from reps and seconds")
    func reportingSchemasSaySo() throws {
        #expect(ToolCatalog.volumeByMuscleDefinition.description.contains("distance"))
        #expect(ToolCatalog.exerciseHistoryDefinition.description.contains("distance"))
        #expect(ToolCatalog.recentSessionsDefinition.description.contains("distance"))
    }

    // MARK: - A carry survives the trip to the phone as bytes

    @Test("A plan prescribing a carry is written to the folder and reads back intact")
    func carriedPlanSurvivesTheFile() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "carry-plan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let documents = DocumentFolder(directory: folder)
        let outcome = try makeRunner(documents: documents, catalog: try carryCatalog()).call(
            ToolCatalog.writePlan,
            arguments: [
                "title": "Carry block",
                "blocks": [["days": [[
                    "weekday": "monday",
                    "exercises": [[
                        "exerciseID": "kettlebell-farmers-carry",
                        "displayName": "Kettlebell Farmers Carry",
                        "sets": 3, "repRange": "40 metres",
                    ]],
                ]]]],
            ])
        #expect(outcome.failureMessage == nil)

        // Read back through the phone's own decoder, from the bytes on disk —
        // the one direction an encode-then-decode round trip cannot vouch for.
        let read = try #require(try documents.readPlan())
        let exercise = try #require(read.blocks.first?.days.first?.exercises.first)

        #expect(exercise.repRange == "40 metres")
        #expect(RepRange("40 metres").isEmpty, "a carry states no rep count")
        #expect(WorkMeasure("40 metres") == .distance(.metres))
        #expect(WorkDistance("40 metres").distance == Distance(value: 40, unit: .metres))
    }
}
