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
            "title": "Autumn strength", "goal": "Bigger squat", "weekCount": 4,
            "durationMinutes": 60, "notes": "Eat.", "days": [Self.squatDay],
        ])
        let report = try #require(outcome.report)
        let written = try #require(documents.lastWrittenPlan)

        #expect(written.title == "Autumn strength")
        #expect(written.goal == "Bigger squat")
        #expect(written.weekCount == 4)
        #expect(report["plan"]?["title"]?.stringValue == "Autumn strength")
        #expect(report["writtenTo"]?.stringValue == documents.planLocation)
    }

    @Test("Every prescribed value is recorded exactly, none of it adjusted")
    func valuesAreRecordedVerbatim() throws {
        let (_, documents) = try plan(["days": [Self.squatDay]])
        let exercise = try #require(documents.lastWrittenPlan?.days.first?.exercises.first)

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
        let exercise = try #require(documents.lastWrittenPlan?.days.first?.exercises.first)

        #expect(exercise.restSeconds == nil)
        #expect(exercise.suggestedLoad == nil)
        #expect(exercise.repRange == "")
    }

    @Test("A rest day named on purpose is written as a day with no exercises")
    func emptyDayIsWritten() throws {
        let (_, documents) = try plan(["days": [["weekday": "wednesday", "focus": "Rest"]]])

        #expect(documents.lastWrittenPlan?.days.first?.exercises.isEmpty == true)
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

        #expect(documents.lastWrittenPlan?.days.first?.weekday == .thursday)
    }

    @Test("A weekday given as Calendar's number is understood")
    func weekdayByNumber() throws {
        let (_, documents) = try plan(["days": [["weekday": 5]]])

        #expect(documents.lastWrittenPlan?.days.first?.weekday == .thursday)
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
}
