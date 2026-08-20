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
        #expect(written.weekCount == 1)
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
        let weeks: [JSONValue] = (0..<8).map {
            Self.week("Week \($0 + 1)", load: 275 + Double($0) * 10)
        }
        let (outcome, documents) = try plan([
            "title": "Eight-week block", "weeks": .array(weeks),
        ])

        #expect(outcome.failureMessage == nil)
        let reported = try #require(outcome.report?["plan"]?["weeks"]?.arrayValue)
        #expect(reported.count == 8, "seven weeks must not vanish")
        #expect(reported.first?["days"]?.arrayValue?.count == 1)
        #expect(documents.lastWrittenPlan != nil)
    }

    @Test("Each week keeps the load it was written with, so they differ")
    func weeksKeepTheirOwnLoads() throws {
        let (outcome, _) = try plan([
            "weeks": [Self.week("Accumulation", load: 275), Self.week("Peak", load: 315)]
        ])
        let reported = try #require(outcome.report?["plan"]?["weeks"]?.arrayValue)
        let loads = reported.map {
            $0["days"]?.arrayValue?.first?["exercises"]?.arrayValue?
                .first?["suggestedLoad"]?["value"]
        }

        #expect(loads == [.number(275), .number(315)])
    }

    @Test("A deload week arrives with its flag and its label intact")
    func deloadWeekSurvives() throws {
        let (outcome, _) = try plan([
            "weeks": [
                Self.week("Accumulation", load: 315),
                Self.week("Back off", load: 225, isDeload: true),
            ]
        ])
        let reported = try #require(outcome.report?["plan"]?["weeks"]?.arrayValue)

        #expect(reported.first?["isDeload"] == .bool(false))
        #expect(reported.last?["isDeload"] == .bool(true))
        #expect(reported.last?["label"] == .string("Back off"))
    }

    @Test("A week the plan did not name carries no label rather than an invented one")
    func unlabelledWeekStaysUnlabelled() throws {
        let (outcome, _) = try plan(["weeks": [["days": [Self.squatDay]]]])
        let reported = try #require(outcome.report?["plan"]?["weeks"]?.arrayValue)

        // Read through `objectValue`, since the subscript answers `nil` for an
        // explicit null and this is exactly the difference being asserted.
        #expect(reported.first?.objectValue?["label"] == .null)
        #expect(reported.first?["isDeload"] == .bool(false))
    }

    @Test("A block written as bare days is one week, as it always was")
    func bareDaysAreOneWeek() throws {
        let (outcome, _) = try plan(["days": [Self.squatDay]])
        let reported = try #require(outcome.report?["plan"]?["weeks"]?.arrayValue)

        #expect(reported.count == 1)
        #expect(reported.first?["days"]?.arrayValue?.count == 1)
    }

    @Test("A stated weekCount that disagrees with the weeks sent is refused, not ignored")
    func weekCountThatDisagreesIsRefused() throws {
        let (outcome, documents) = try plan([
            "weekCount": 8, "weeks": [Self.week("Accumulation", load: 275)],
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
            "weeks": [["intensityWave": "ascending", "days": [Self.squatDay]]]
        ])

        #expect(try #require(outcome.failureMessage).contains("intensityWave"))
        #expect(documents.lastWrittenPlan == nil)
    }

    @Test("Both weeks and days at once is refused rather than one being dropped")
    func weeksAndDaysTogetherAreRefused() throws {
        let (outcome, documents) = try plan([
            "weeks": [Self.week("Accumulation", load: 275)], "days": [Self.squatDay],
        ])
        let message = try #require(outcome.failureMessage)

        #expect(message.contains("weeks"))
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
            written.weeks.first?.days.first?.entries.first?.exercises.first)
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
        #expect(written.weeks.first?.days.first?.entries.first?
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
