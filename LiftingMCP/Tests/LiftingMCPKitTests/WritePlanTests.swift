import Foundation
import Testing
import LiftingKit
@testable import LiftingMCPKit

@Suite("write_plan")
struct WritePlanTests {

    private func plan(_ arguments: JSONValue) throws -> (ToolOutcome, InMemoryDocuments) {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot())
        let outcome = try makeRunner(documents: documents)
            .call(ToolCatalog.writePlan, arguments: arguments)
        return (outcome, documents)
    }

    private static let squatDay: JSONValue = [
        "weekday": "monday", "focus": "Lower", "durationMinutes": 60,
        "exercises": [[
            "exerciseID": "barbell-squat", "displayName": "Barbell Squat",
            "sets": 7, "repRange": "3-5", "restSeconds": 240,
            "suggestedLoad": ["value": 315.0, "unit": "lb"],
            "tempo": "3-0-1-0", "notes": "Belt from the third set.",
        ]],
    ]

    // MARK: - What was written is what was said

    @Test("The plan lands in the folder and comes back as it was written")
    func writesAndReturnsThePlan() throws {
        let (outcome, documents) = try plan([
            "title": "Autumn strength", "goal": "Bigger squat", "weekCount": 1,
            "durationMinutes": 60, "notes": "Eat.", "days": [Self.squatDay],
        ])
        let report = try #require(outcome.report)
        let written = try #require(documents.lastWrittenPlan)

        #expect(written.title == "Autumn strength")
        #expect(written.goal == "Bigger squat")
        // Stated as 1 and one week was sent, so it agrees rather than being
        // taken on trust.
        #expect(written.blockCount == 1)
        #expect(report["plan"]?["title"]?.stringValue == "Autumn strength")
        #expect(report["writtenTo"]?.stringValue == documents.planLocation)
    }

    @Test("The note the coach wrote lands in the document and comes back in the report")
    func noteIsWrittenAndReported() throws {
        let note = "Three heavy weeks then a deload. Tell me if the shoulder complains."
        let (outcome, documents) = try plan([
            "title": "Autumn strength", "notes": .string(note), "days": [Self.squatDay],
        ])
        let report = try #require(outcome.report)

        #expect(documents.lastWrittenPlan?.notes == note)
        #expect(report["plan"]?["notes"]?.stringValue == note)
    }

    @Test("A plan written with no note states none rather than an empty one")
    func absentNoteStaysAbsent() throws {
        let (_, documents) = try plan(["days": [Self.squatDay]])

        #expect(documents.lastWrittenPlan?.notes == nil)
    }

    @Test("Every prescribed value is recorded exactly, none of it adjusted")
    func valuesAreRecordedVerbatim() throws {
        let (_, documents) = try plan(["days": [Self.squatDay]])
        let exercise = try #require(documents.lastWrittenPlan?.everyDay.first?.exercises.first)

        #expect(exercise.sets == 7)
        #expect(exercise.repRange == "3-5")
        #expect(exercise.restSeconds == 240)
        #expect(exercise.suggestedLoad == Mass(value: 315, unit: .pounds))
        #expect(exercise.tempo == "3-0-1-0")
    }

    @Test("A prescription that states no rest and no load keeps both absent")
    func absencesStayAbsent() throws {
        let (_, documents) = try plan([
            "days": [[
                "weekday": "monday",
                "exercises": [[
                    "exerciseID": "push-up", "displayName": "Push Up", "sets": 3,
                ]],
            ]]
        ])
        let exercise = try #require(documents.lastWrittenPlan?.everyDay.first?.exercises.first)

        #expect(exercise.restSeconds == nil)
        #expect(exercise.suggestedLoad == nil)
        #expect(exercise.repRange == "")
    }

    @Test("A rest day named on purpose is written as a day with no exercises")
    func emptyDayIsWritten() throws {
        let (_, documents) = try plan(["days": [["weekday": "wednesday", "focus": "Rest"]]])

        #expect(documents.lastWrittenPlan?.everyDay.first?.exercises.isEmpty == true)
    }

    // MARK: - A block is more than one week

    /// One week of the block, at a stated load, so eight of them are eight
    /// genuinely different weeks rather than the same week eight times.
    private static func week(
        _ label: String, load: Double, isDeload: Bool = false
    ) -> JSONValue {
        [
            "label": .string(label), "isDeload": .bool(isDeload),
            "days": [[
                "weekday": "monday", "focus": "Lower",
                "exercises": [[
                    "exerciseID": "barbell-squat", "displayName": "Barbell Squat",
                    "sets": 5, "repRange": "5",
                    "suggestedLoad": ["value": .number(load), "unit": "lb"],
                ]],
            ]],
        ]
    }

    @Test("An eight-week block is written as eight weeks, each with its own days")
    func eightWeeksAreWrittenAsEight() throws {
        let blocks: [JSONValue] = (0..<8).map {
            Self.week("Week \($0 + 1)", load: 275 + Double($0) * 10)
        }
        let (outcome, documents) = try plan([
            "title": "Eight-block routine", "blocks": .array(blocks),
        ])

        #expect(outcome.failureMessage == nil)
        let reported = try #require(outcome.report?["plan"]?["blocks"]?.arrayValue)
        #expect(reported.count == 8, "seven weeks must not vanish")
        #expect(reported.first?["days"]?.arrayValue?.count == 1)
        #expect(documents.lastWrittenPlan != nil)
    }

    @Test("Each week keeps the load it was written with, so they differ")
    func weeksKeepTheirOwnLoads() throws {
        let (outcome, _) = try plan([
            "blocks": [Self.week("Accumulation", load: 275), Self.week("Peak", load: 315)]
        ])
        let reported = try #require(outcome.report?["plan"]?["blocks"]?.arrayValue)
        let loads = reported.map {
            $0["days"]?.arrayValue?.first?["exercises"]?.arrayValue?
                .first?["suggestedLoad"]?["value"]
        }

        #expect(loads == [.number(275), .number(315)])
    }

    @Test("A deload week arrives with its flag and its label intact")
    func deloadWeekSurvives() throws {
        let (outcome, _) = try plan([
            "blocks": [
                Self.week("Accumulation", load: 315),
                Self.week("Back off", load: 225, isDeload: true),
            ]
        ])
        let reported = try #require(outcome.report?["plan"]?["blocks"]?.arrayValue)

        #expect(reported.first?["isDeload"] == .bool(false))
        #expect(reported.last?["isDeload"] == .bool(true))
        #expect(reported.last?["label"] == .string("Back off"))
    }

    @Test("A week the plan did not name carries no label rather than an invented one")
    func unlabelledWeekStaysUnlabelled() throws {
        let (outcome, _) = try plan(["blocks": [["days": [Self.squatDay]]]])
        let reported = try #require(outcome.report?["plan"]?["blocks"]?.arrayValue)

        // Read through `objectValue`, since the subscript answers `nil` for an
        // explicit null and this is exactly the difference being asserted.
        #expect(reported.first?.objectValue?["label"] == .null)
        #expect(reported.first?["isDeload"] == .bool(false))
    }

    @Test("A block written as bare days is one week, as it always was")
    func bareDaysAreOneWeek() throws {
        let (outcome, _) = try plan(["days": [Self.squatDay]])
        let reported = try #require(outcome.report?["plan"]?["blocks"]?.arrayValue)

        #expect(reported.count == 1)
        #expect(reported.first?["days"]?.arrayValue?.count == 1)
    }

    @Test("A stated weekCount that disagrees with the weeks sent is refused, not ignored")
    func weekCountThatDisagreesIsRefused() throws {
        let (outcome, documents) = try plan([
            "weekCount": 8, "blocks": [Self.week("Accumulation", load: 275)],
        ])
        let message = try #require(outcome.failureMessage)

        #expect(message.contains("8"))
        #expect(message.contains("1"))
        #expect(documents.lastWrittenPlan == nil, "an ignored field is how seven weeks vanished")
    }

    // MARK: - Refused rather than discarded

    @Test("A key the format does not have is refused with the key named")
    func unknownExerciseKeyIsNamed() throws {
        let (outcome, documents) = try plan([
            "days": [[
                "weekday": "monday",
                "exercises": [[
                    "exerciseID": "barbell-squat", "displayName": "Barbell Squat",
                    "sets": 5, "dropSets": 2,
                ]],
            ]]
        ])
        let message = try #require(outcome.failureMessage)

        #expect(message.contains("dropSets"))
        #expect(documents.lastWrittenPlan == nil, "a refused plan must write nothing")
    }

    @Test("An unknown key at the top of the plan is refused too")
    func unknownBlockKeyIsNamed() throws {
        let (outcome, documents) = try plan([
            "periodizationModel": "block", "days": [Self.squatDay],
        ])

        #expect(try #require(outcome.failureMessage).contains("periodizationModel"))
        #expect(documents.lastWrittenPlan == nil)
    }

    @Test("An unknown key inside a week is refused")
    func unknownWeekKeyIsNamed() throws {
        let (outcome, documents) = try plan([
            "blocks": [["intensityWave": "ascending", "days": [Self.squatDay]]]
        ])

        #expect(try #require(outcome.failureMessage).contains("intensityWave"))
        #expect(documents.lastWrittenPlan == nil)
    }

    @Test("Both weeks and days at once is refused rather than one being dropped")
    func weeksAndDaysTogetherAreRefused() throws {
        let (outcome, documents) = try plan([
            "blocks": [Self.week("Accumulation", load: 275)], "days": [Self.squatDay],
        ])
        let message = try #require(outcome.failureMessage)

        #expect(message.contains("blocks"))
        #expect(message.contains("days"))
        #expect(documents.lastWrittenPlan == nil)
    }

    // MARK: - The one thing it checks

    @Test("An exercise the catalog does not have fails the call and names the ID")
    func unknownExerciseIsNamed() throws {
        let (outcome, documents) = try plan([
            "days": [[
                "weekday": "monday",
                "exercises": [[
                    "exerciseID": "barbell-bench-pres", "displayName": "Bench", "sets": 3,
                ]],
            ]]
        ])

        let message = try #require(outcome.failureMessage)
        #expect(message.contains("barbell-bench-pres"))
        #expect(message.contains(ToolCatalog.listExercises))
        #expect(documents.lastWrittenPlan == nil, "a rejected plan must write nothing")
    }

    @Test("One bad ID among good ones still writes nothing at all")
    func oneBadIDRejectsTheWholePlan() throws {
        let (outcome, documents) = try plan([
            "days": [
                Self.squatDay,
                ["weekday": "thursday",
                 "exercises": [["exerciseID": "chin-ups", "displayName": "Chin Up", "sets": 3]]],
            ]
        ])

        #expect(outcome.failureMessage != nil)
        #expect(documents.lastWrittenPlan == nil)
    }

    @Test("A plan with no days at all is refused rather than written as a plan")
    func missingDaysIsRefused() throws {
        let (outcome, documents) = try plan(["title": "Nothing"])

        #expect(outcome.failureMessage != nil)
        #expect(documents.lastWrittenPlan == nil)
    }

    // MARK: - Metadata the server is the right one to supply

    @Test("The document's identity, catalog version and timestamp are stamped by the server")
    func metadataIsStamped() throws {
        let (_, documents) = try plan(["days": [Self.squatDay]])
        let written = try #require(documents.lastWrittenPlan)

        #expect(written.catalogVersion == 5, "the version the IDs were just checked against")
        #expect(written.generatedAt == referenceNow)
        #expect(written.version == PlanDocument.currentVersion)
    }

    @Test("Two plans written in a row get different identities, so neither is a no-op import")
    func identitiesAreDistinct() throws {
        let (_, first) = try plan(["days": [Self.squatDay]])
        let (_, second) = try plan(["days": [Self.squatDay]])

        #expect(first.lastWrittenPlan?.id != second.lastWrittenPlan?.id)
    }

    // MARK: - Weekdays, however they are written

    @Test("A weekday named in words is understood")
    func weekdayByName() throws {
        let (_, documents) = try plan(["days": [["weekday": "thursday"]]])

        #expect(documents.lastWrittenPlan?.everyDay.first?.weekday == .thursday)
    }

    @Test("A weekday given as Calendar's number is understood")
    func weekdayByNumber() throws {
        let (_, documents) = try plan(["days": [["weekday": 5]]])

        #expect(documents.lastWrittenPlan?.everyDay.first?.weekday == .thursday)
    }

    @Test("A weekday that is neither is refused with the offending value named")
    func unusableWeekdayIsNamed() throws {
        let (outcome, documents) = try plan(["days": [["weekday": "Frunsday"]]])

        #expect(try #require(outcome.failureMessage).contains("Frunsday"))
        #expect(documents.lastWrittenPlan == nil)
    }

    // MARK: - A folder that will not take the write

    @Test("A write that fails is reported rather than looking like it landed")
    func failedWriteIsReported() throws {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot())
        documents.breakTransport()
        let outcome = try makeRunner(documents: documents)
            .call(ToolCatalog.writePlan, arguments: ["days": [Self.squatDay]])

        #expect(try #require(outcome.failureMessage).contains(documents.planLocation))
    }

    // MARK: - The name is the catalog's

    @Test("A plan that states no display name is written with the catalog's")
    func nameIsFilledFromTheCatalog() throws {
        // The name is display only and both ends link the same catalog, so
        // asking for it was a key per exercise whose only outcomes were
        // agreeing with the catalog or disagreeing with it.
        let documents = InMemoryDocuments()
        let outcome = try makeRunner(documents: documents).call(
            ToolCatalog.writePlan,
            arguments: [
                "title": "Autumn",
                "days": [["weekday": "monday", "exercises": [
                    ["exerciseID": "barbell-bench-press", "sets": 3, "repRange": "5"]
                ]]],
            ])

        #expect(outcome.report != nil)
        let written = try #require(documents.lastWrittenPlan)
        let exercise = try #require(
            written.blocks.first?.days.first?.entries.first?.exercises.first)
        #expect(exercise.displayName == "Barbell Bench Press")
    }

    @Test("A name he did state is written as he stated it")
    func statedNameIsKept() throws {
        let documents = InMemoryDocuments()
        _ = try makeRunner(documents: documents).call(
            ToolCatalog.writePlan,
            arguments: [
                "title": "Autumn",
                "days": [["weekday": "monday", "exercises": [
                    ["exerciseID": "barbell-bench-press", "displayName": "Comp Bench",
                     "sets": 3]
                ]]],
            ])

        let written = try #require(documents.lastWrittenPlan)
        #expect(written.blocks.first?.days.first?.entries.first?
            .exercises.first?.displayName == "Comp Bench")
    }

    @Test("An unknown ID is still refused as an unknown ID, not named")
    func unknownIDIsStillRefused() throws {
        let documents = InMemoryDocuments()
        let outcome = try makeRunner(documents: documents).call(
            ToolCatalog.writePlan,
            arguments: [
                "title": "Autumn",
                "days": [["weekday": "monday", "exercises": [
                    ["exerciseID": "not-an-exercise", "sets": 3]
                ]]],
            ])

        #expect(outcome.failureMessage?.contains("not-an-exercise") == true)
        #expect(documents.lastWrittenPlan == nil)
    }
}

/// The identity that lets a routine grow a week at a time.
@Suite("A routine that grows")
struct WritePlanRoutineIdentityTests {

    private func write(_ arguments: JSONValue) throws -> (PlanDocument?, ToolOutcome) {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot())
        let outcome = try makeRunner(documents: documents).writePlan(arguments)
        return (documents.lastWrittenPlan, outcome)
    }

    private var oneWeek: JSONValue {
        ["blocks": [["days": [["weekday": 2, "focus": "Push", "exercises": [
            ["exerciseID": "barbell-bench-press", "sets": 3, "repRange": "5"]
        ]]]]]]
    }

    @Test("A stated routine id is the document's, so the block lands on that routine")
    func statedIdentityIsKept() throws {
        let id = UUID()
        var arguments = oneWeek.objectValue ?? [:]
        arguments["routineID"] = .string(id.uuidString)

        let (written, _) = try write(.object(arguments))

        #expect(written?.id == id)
    }

    @Test("No routine id means a new routine, with an identity of its own")
    func omittedIdentityIsFresh() throws {
        let (first, _) = try write(oneWeek)
        let (second, _) = try write(oneWeek)

        #expect(first?.id != second?.id)
    }

    @Test("Something that is not an id is refused rather than quietly replaced")
    func malformedIdentityIsRefused() throws {
        var arguments = oneWeek.objectValue ?? [:]
        arguments["routineID"] = .string("the autumn one")

        let (written, outcome) = try write(.object(arguments))

        #expect(written == nil)
        if case .failure(let message) = outcome {
            #expect(message.contains("the autumn one"))
        } else {
            Issue.record("a routineID that is not an id must fail the call")
        }
    }
}
/// The refusal that used to happen only on the phone, where the coach who wrote
/// the plan could not see it.
@Suite("A block already trained")
struct WritePlanTrainedBlockTests {

    private static let bench = "barbell-bench-press"

    /// A routine of one block, one Monday push session at `load`, trained or
    /// not as `trained` says.
    private func stored(id: UUID, load: Double, trained: Bool)
        -> (routine: SnapshotRoutine, log: [LoggedSetRecord])
    {
        fixtureRoutine(
            id: id, title: "Autumn strength", startDate: daysAgo(14),
            blocks: [(label: "Accumulation", isDeload: false, days: [
                fixtureDay(
                    weekday: .monday, focus: "Push",
                    completedAt: trained ? daysAgo(2) : nil,
                    exercises: [
                        prescribed(
                            Self.bench, "Barbell Bench Press", sets: 3, reps: "5",
                            load: load, rest: 180,
                            logged: trained ? [set(0, load, 5, at: daysAgo(2))] : [])
                    ])
            ])])
    }

    private func arguments(id: UUID, load: Double, blocks: Int) -> JSONValue {
        var written: [JSONValue] = []
        for index in 0..<blocks {
            written.append([
                "label": index == 0 ? "Accumulation" : "Intensification",
                "days": [["weekday": 2, "focus": "Push", "exercises": [
                    ["exerciseID": .string(Self.bench), "displayName": "Barbell Bench Press",
                     "sets": 3, "repRange": "5", "restSeconds": 180,
                     "suggestedLoad": ["value": JSONValue.number(load), "unit": "lb"]],
                ]]],
            ])
        }
        return ["routineID": .string(id.uuidString), "title": "Autumn strength",
                "blocks": .array(written)]
    }

    @Test("Rewriting a block he has trained fails the call rather than the import")
    func aTrainedBlockIsRefusedHere() throws {
        // It was refused on his phone, quietly, after this tool had already
        // answered "Written." — the coach believing a plan landed when none of
        // it did.
        let id = UUID()
        let documents = InMemoryDocuments(
            snapshot: fixtureSnapshot(blocks: [stored(id: id, load: 185, trained: true)]))
        let outcome = try makeRunner(documents: documents).writePlan(
            arguments(id: id, load: 245, blocks: 1))

        #expect(documents.lastWrittenPlan == nil, "nothing written, as the message says")
        if case .failure(let message) = outcome {
            #expect(message.contains("block 1"))
            #expect(message.contains("already trained"))
        } else {
            Issue.record("rewriting a trained block has to fail the call")
        }
    }

    @Test("Adding a block beside one he has trained is the ordinary week and goes through")
    func aLaterBlockIsFine() throws {
        let id = UUID()
        let documents = InMemoryDocuments(
            snapshot: fixtureSnapshot(blocks: [stored(id: id, load: 185, trained: true)]))
        let outcome = try makeRunner(documents: documents).writePlan(
            arguments(id: id, load: 185, blocks: 2))

        #expect(outcome.failureMessage == nil)
        #expect(documents.lastWrittenPlan?.blocks.count == 2)
    }

    @Test("A block nobody has trained is the coach's to rewrite")
    func anUntrainedBlockIsFine() throws {
        let id = UUID()
        let documents = InMemoryDocuments(
            snapshot: fixtureSnapshot(blocks: [stored(id: id, load: 185, trained: false)]))
        let outcome = try makeRunner(documents: documents).writePlan(
            arguments(id: id, load: 245, blocks: 1))

        #expect(outcome.failureMessage == nil)
        #expect(documents.lastWrittenPlan?.blocks.first?.days.first?
            .entries.first?.exercises.first?.suggestedLoad == Mass(value: 245, unit: .pounds))
    }
}
