import Foundation
import Testing
import LiftingKit
@testable import LiftingMCPKit

@Suite("list_exercises")
struct ListExercisesTests {

    private func list(
        _ arguments: JSONValue, profile: SnapshotProfile? = fixtureProfile()
    ) throws -> JSONValue {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot(profile: profile))
        let outcome = try makeRunner(documents: documents)
            .call(ToolCatalog.listExercises, arguments: arguments)
        return try #require(outcome.report)
    }

    private func ids(_ report: JSONValue) throws -> [String] {
        try #require(report["exercises"]?.arrayValue).compactMap { $0["id"]?.stringValue }
    }

    // MARK: - Real IDs, and enough beside them to choose without a second call

    @Test("Every entry carries the real ID and enough context to pick a movement")
    func entriesAreSelfSufficient() throws {
        let report = try list(["query": "barbell bench press"])
        let entries = try #require(report["exercises"]?.arrayValue)
        let entry = try #require(entries.first)

        #expect(entry["id"]?.stringValue == "barbell-bench-press")
        #expect(entry["name"]?.stringValue == "Barbell Bench Press")
        #expect(entry["pattern"]?.stringValue == "horizontal press")
        #expect(entry["equipment"]?.stringValue == "barbell")
        #expect(entry["primaryMuscles"] == ["chest"])
        #expect(entry["secondaryMuscles"] == ["triceps", "shoulders"])
        #expect(entry["mechanic"]?.stringValue == "compound")
        #expect(entry["difficulty"]?.stringValue == "intermediate")
    }

    @Test("The whole catalog comes back when nothing narrows it")
    func unfilteredListsEverything() throws {
        #expect(try ids(list([:])).count == 8)
    }

    // MARK: - Narrowing

    @Test("Filtering by primary muscle returns only movements that train it")
    func filtersByMuscle() throws {
        #expect(
            try ids(list(["muscle": "chest"])).sorted()
                == ["barbell-bench-press", "dumbbell-bench-press", "push-up"])
    }

    @Test("Filtering by pattern returns only that pattern")
    func filtersByPattern() throws {
        #expect(try ids(list(["pattern": "squat"])) == ["barbell-squat"])
    }

    @Test("Filtering by equipment returns only what that equipment can do")
    func filtersByEquipment() throws {
        #expect(try ids(list(["equipment": "dumbbell"])) == ["dumbbell-bench-press"])
    }

    @Test("A bare string means the same as a one-element list")
    func scalarAndListFiltersAgree() throws {
        #expect(try ids(list(["muscle": "chest"])) == (try ids(list(["muscle": ["chest"]]))))
    }

    @Test("Free text matches names and aliases")
    func searchesFreeText() throws {
        #expect(try ids(list(["query": "bent over barbell row"])) == ["barbell-bent-over-row"])
    }

    @Test("The limit caps the entries while the report still says how many matched")
    func limitCapsWithoutHidingTheTotal() throws {
        let report = try list(["limit": 2])

        #expect(try ids(report).count == 2)
        #expect(report["totalMatching"] == 8)
    }

    // MARK: - Narrowed to what this lifter can actually perform

    @Test("A lifter with only his bodyweight is not shown barbell movements")
    func filtersToAvailableEquipment() throws {
        let report = try list([:], profile: fixtureProfile(
            equipmentAccess: .bodyweight, availableEquipment: [.bodyweight]))

        #expect(try ids(report) == ["push-up"])
    }

    @Test("An avoided exercise is left out")
    func excludesAvoidedExercises() throws {
        let report = try list([:], profile: fixtureProfile(
            avoidedExercises: [ExerciseID(rawValue: "barbell-deadlift")]))

        #expect(!(try ids(report).contains("barbell-deadlift")))
    }

    @Test("An avoided pattern is left out")
    func excludesAvoidedPatterns() throws {
        let report = try list([:], profile: fixtureProfile(avoidedPatterns: [.hinge]))

        #expect(!(try ids(report).contains("barbell-deadlift")))
    }

    @Test("includeUnavailable brings back what was ruled out, so what a lifter cannot do is never indistinguishable from what does not exist")
    func includeUnavailableBypassesNarrowing() throws {
        let report = try list(
            ["includeUnavailable": true],
            profile: fixtureProfile(
                equipmentAccess: .bodyweight, availableEquipment: [.bodyweight],
                avoidedExercises: [ExerciseID(rawValue: "barbell-deadlift")]))

        #expect(try ids(report).count == 8)
    }

    @Test("The report states the narrowing it applied rather than applying it silently")
    func reportsItsOwnFilter() throws {
        let report = try list(["muscle": "chest"], profile: fixtureProfile(
            equipmentAccess: .bodyweight, availableEquipment: [.bodyweight],
            avoidedPatterns: [.hinge]))
        let applied = try #require(report["appliedFilter"])

        #expect(applied["muscle"] == ["chest"])
        #expect(applied["lifterEquipment"] == ["bodyweight"])
        #expect(applied["avoidedPatterns"] == ["hinge"])
    }

    @Test("A lifter who has not been set up yet is narrowed by nothing, and told so")
    func noProfileNarrowsByNothing() throws {
        let report = try list([:], profile: nil)

        #expect(try ids(report).count == 8)
        // Reported as JSON null: nothing is known about his equipment, which is
        // a different answer from an empty list of equipment he has.
        #expect(report["appliedFilter"]?.objectValue?["lifterEquipment"] == .null)
        #expect(report["note"]?.stringValue?.isEmpty == false)
    }
}
