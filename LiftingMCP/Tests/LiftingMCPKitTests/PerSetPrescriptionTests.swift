import Foundation
import Testing
import LiftingKit
@testable import LiftingMCPKit

/// Writing a prescription whose sets differ, and reading a prescribed effort
/// back beside the effort that was logged.
///
/// The second half is the point of the first: a coach who can state an RPE
/// target but never read it back against what the lifter reported cannot judge
/// a session, so both directions are asserted here together.
@Suite("Per-set prescription and intensity")
struct PerSetPrescriptionTests {

    private func plan(_ arguments: JSONValue) throws -> (ToolOutcome, InMemoryDocuments) {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot())
        let outcome = try makeRunner(documents: documents)
            .call(ToolCatalog.writePlan, arguments: arguments)
        return (outcome, documents)
    }

    private func day(_ exercises: [JSONValue]) -> JSONValue {
        ["weekday": "monday", "focus": "Lower", "exercises": .array(exercises)]
    }

    // MARK: - Sets that differ

    @Test("A drop set is written as the four sets it is, the last one lighter")
    func dropSetIsWritten() throws {
        let (outcome, documents) = try plan([
            "days": [day([[
                "exerciseID": "barbell-bench-press", "displayName": "Barbell Bench Press",
                "repRange": "8",
                "suggestedLoad": ["value": 100.0, "unit": "kg"],
                "sets": [
                    [:], [:], [:],
                    [
                        "suggestedLoad": ["value": 70.0, "unit": "kg"],
                        "repRange": "AMRAP", "notes": "Drop set, to failure",
                    ],
                ],
            ]])]
        ])
        #expect(outcome.failureMessage == nil)
        let exercise = try #require(documents.lastWrittenPlan?.everyDay.first?.exercises.first)

        #expect(exercise.sets == 4)
        #expect(exercise.prescribedSets.map { $0.suggestedLoad?.value } == [100, 100, 100, 70])
        #expect(exercise.prescribedSets.map(\.repRange) == ["8", "8", "8", "AMRAP"])
        #expect(exercise.prescribedSets.last?.notes == "Drop set, to failure")
    }

    @Test("A ramping load is written as the loads it was written with, in order")
    func rampingLoadIsWritten() throws {
        let (outcome, documents) = try plan([
            "days": [day([[
                "exerciseID": "barbell-squat", "displayName": "Barbell Squat",
                "repRange": "5",
                "sets": [
                    ["suggestedLoad": ["value": 60.0, "unit": "kg"]],
                    ["suggestedLoad": ["value": 70.0, "unit": "kg"]],
                    ["suggestedLoad": ["value": 80.0, "unit": "kg"]],
                ],
            ]])]
        ])
        #expect(outcome.failureMessage == nil)
        let exercise = try #require(documents.lastWrittenPlan?.everyDay.first?.exercises.first)

        #expect(exercise.sets == 3)
        #expect(exercise.prescribedSets.map { $0.suggestedLoad?.value } == [60, 70, 80])
        #expect(exercise.prescribedSets.allSatisfy { $0.repRange == "5" })
    }

    @Test("The sets that were written come back in the report, not just a count")
    func perSetIsReportedBack() throws {
        let (outcome, _) = try plan([
            "days": [day([[
                "exerciseID": "barbell-squat", "displayName": "Barbell Squat",
                "sets": [
                    ["repRange": "5", "suggestedLoad": ["value": 60.0, "unit": "kg"]],
                    ["repRange": "3", "suggestedLoad": ["value": 80.0, "unit": "kg"]],
                ],
            ]])]
        ])
        let reported = try #require(
            outcome.report?["plan"]?["weeks"]?[0]?["days"]?[0]?["exercises"]?[0])

        #expect(reported["sets"]?.intValue == 2)
        let sets = try #require(reported["prescribedSets"]?.arrayValue)
        #expect(sets.count == 2)
        #expect(sets.first?["repRange"] == .string("5"))
        #expect(sets.last?["suggestedLoad"]?["value"] == .number(80))
    }

    @Test("A uniform prescription is still written as a count, not as a list")
    func uniformStaysACount() throws {
        let (_, documents) = try plan([
            "days": [day([[
                "exerciseID": "barbell-squat", "displayName": "Barbell Squat",
                "sets": 3, "repRange": "8-12",
            ]])]
        ])
        let exercise = try #require(documents.lastWrittenPlan?.everyDay.first?.exercises.first)

        #expect(exercise.sets == 3)
        #expect(exercise.statedSets.isEmpty, "three sets of eight is not three objects")
        #expect(exercise.prescribedSets.count == 3)
    }

    @Test("An unknown key inside a listed set is refused with the key named")
    func unknownKeyInASetIsRefused() throws {
        let (outcome, documents) = try plan([
            "days": [day([[
                "exerciseID": "barbell-squat", "displayName": "Barbell Squat",
                "sets": [["clusterRest": 20]],
            ]])]
        ])

        #expect(try #require(outcome.failureMessage).contains("clusterRest"))
        #expect(documents.lastWrittenPlan == nil)
    }

    // MARK: - Intensity, on whatever scale it was stated

    private func target(_ scale: String, _ value: String) throws -> IntensityTarget {
        let (outcome, documents) = try plan([
            "days": [day([[
                "exerciseID": "barbell-squat", "displayName": "Barbell Squat", "sets": 3,
                "intensity": ["scale": .string(scale), "value": .string(value)],
            ]])]
        ])
        #expect(outcome.failureMessage == nil)
        return try #require(documents.lastWrittenPlan?.everyDay.first?.exercises.first?.intensity)
    }

    @Test("An RPE target is written as an RPE target")
    func rpeIsWritten() throws {
        let intensity = try target("rpe", "8")
        #expect(intensity.scale == .rpe)
        #expect(intensity.value == "8")
    }

    @Test("A reps-in-reserve target is written as one, not converted into an RPE")
    func rirIsWritten() throws {
        let intensity = try target("rir", "2")
        #expect(intensity.scale == .repsInReserve)
        #expect(intensity.value == "2")
    }

    @Test("A percentage of one-rep max is written as the percentage it was written as")
    func percentIsWritten() throws {
        let intensity = try target("percent1rm", "80")
        #expect(intensity.scale == .percentOfOneRepMax)
        #expect(intensity.value == "80")
    }

    @Test("A scale this server has never heard of is written rather than refused")
    func unknownScaleIsWritten() throws {
        let intensity = try target("metres-per-second", "0.45")
        #expect(intensity.scale == IntensityScale(rawValue: "metres-per-second"))
        #expect(intensity.scale.isKnown == false)
        #expect(intensity.value == "0.45")
    }

    @Test("An exercise with no intensity target is written with none")
    func absentIntensityStaysAbsent() throws {
        let (_, documents) = try plan([
            "days": [day([[
                "exerciseID": "barbell-squat", "displayName": "Barbell Squat",
                "sets": 3, "suggestedLoad": ["value": 100.0, "unit": "kg"],
            ]])]
        ])
        let exercise = try #require(documents.lastWrittenPlan?.everyDay.first?.exercises.first)

        #expect(exercise.intensity == nil, "a load is not an effort target")
        #expect(exercise.prescribedSets.allSatisfy { $0.intensity == nil })
    }

    @Test("An intensity that does not say its scale is refused rather than guessed")
    func intensityWithoutScaleIsRefused() throws {
        let (outcome, documents) = try plan([
            "days": [day([[
                "exerciseID": "barbell-squat", "displayName": "Barbell Squat",
                "sets": 3, "intensity": ["value": "8"],
            ]])]
        ])

        #expect(outcome.failureMessage != nil)
        #expect(documents.lastWrittenPlan == nil)
    }

    @Test("A written intensity comes back in the report")
    func intensityIsReportedBack() throws {
        let (outcome, _) = try plan([
            "days": [day([[
                "exerciseID": "barbell-squat", "displayName": "Barbell Squat", "sets": 3,
                "intensity": ["scale": "rpe", "value": "8-9"],
            ]])]
        ])
        let reported = try #require(
            outcome.report?["plan"]?["weeks"]?[0]?["days"]?[0]?["exercises"]?[0])

        #expect(reported["intensity"]?["scale"] == .string("rpe"))
        #expect(reported["intensity"]?["value"] == .string("8-9"))
    }

    // MARK: - Read back beside what was logged

    private func runner() throws -> ToolRunner {
        try makeRunner(documents: InMemoryDocuments(snapshot: fixtureSnapshot()))
    }

    private func carriedContext() throws -> JSONValue {
        try #require(try runner().contextResource().report)
    }

    @Test("The prescribed intensity rides beside the logged RPE in the carried context")
    func contextCarriesPrescribedIntensity() throws {
        let context = try carriedContext()
        let bench = try #require(
            context["workingWeights"]?.arrayValue?
                .first { $0["exerciseID"] == .string("barbell-bench-press") })

        #expect(bench["rpe"] == .number(9.5), "what he actually gave")
        #expect(bench["prescribedIntensity"]?["scale"] == .string("rpe"))
        #expect(bench["prescribedIntensity"]?["value"] == .string("8"), "what was asked for")
    }

    @Test("A lift with no prescribed intensity reports none rather than a default")
    func contextReportsNoIntensityAsNull() throws {
        let context = try carriedContext()
        let curl = try #require(
            context["workingWeights"]?.arrayValue?
                .first { $0["exerciseID"] == .string("barbell-curl") })

        #expect(curl.objectValue?["prescribedIntensity"] == .null)
    }

    @Test("Exercise history reports the prescribed intensity and sets beside every logged set")
    func historyCarriesPrescription() throws {
        let outcome = try runner()
            .call(ToolCatalog.exerciseHistory, arguments: ["id": "barbell-bench-press"])
        let entry = try #require(outcome.report?["sets"]?.arrayValue?.last)
        let prescribed = try #require(entry["prescribed"])

        #expect(prescribed["intensity"]?["value"] == .string("8"))
        #expect(prescribed["sets"]?.intValue == 3)
        #expect(prescribed["prescribedSets"]?.arrayValue?.count == 3)
        #expect(prescribed["prescribedSets"]?[0]?["repRange"] == .string("5"))
    }

    @Test("A recent session reports what each set asked for beside what each set gave")
    func sessionsCarryPrescription() throws {
        let outcome = try runner().call(ToolCatalog.recentSessions, arguments: [:])
        let session = try #require(outcome.report?["sessions"]?.arrayValue?.first)
        let bench = try #require(
            session["exercises"]?.arrayValue?
                .first { $0["exerciseID"] == .string("barbell-bench-press") })

        #expect(bench["prescribed"]?["intensity"]?["value"] == .string("8"))
        #expect(bench["sets"]?.arrayValue?.compactMap { $0["rpe"] } == [
            .number(8), .number(8.5), .number(9.5),
        ])
    }
}

extension JSONValue {
    /// The element at `index`, or `nil` when this is not an array or is shorter.
    /// Test-only sugar so a report can be read the way it is written.
    subscript(index: Int) -> JSONValue? {
        guard let values = arrayValue, values.indices.contains(index) else { return nil }
        return values[index]
    }
}
