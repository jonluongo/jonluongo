import Foundation
import Testing
import LiftingKit
@testable import LiftingMCPKit

/// Conditioning and mobility through the volume report.
///
/// `volume_by_muscle` answers one question — how much lifting a muscle has
/// taken — and it once answered it by adding up every completed set whatever
/// the exercise was. A forty-minute bike ride reported as quadriceps volume and
/// a held stretch as abdominal volume, and the numbers Claude programs against
/// were wrong in the direction of "he is doing plenty".
///
/// Both halves are asserted here: the work is out of the muscle totals, and it
/// is *still reported*, because a set that was performed and then vanished from
/// every number is the silent discard this project keeps refusing.
@Suite("Conditioning and mobility in the volume report")
struct ConditioningVolumeTests {

    /// A lift, a bike and a stretch, decoded from the shapes `exercises.json`
    /// actually holds — a catalog of its own rather than an addition to the
    /// shared fixture, which other suites count the entries of.
    private func mixedCatalog() throws -> ExerciseCatalog {
        let json = """
            [
              {"id": "barbell-bench-press", "displayName": "Barbell Bench Press",
               "primaryMuscles": ["chest"], "secondaryMuscles": ["triceps", "shoulders"],
               "equipment": "barbell", "pattern": "horizontal press", "force": "push",
               "mechanic": "compound", "category": "strength", "difficulty": "intermediate"},
              {"id": "assault-bike", "displayName": "Assault Bike",
               "primaryMuscles": ["quadriceps"], "secondaryMuscles": [],
               "equipment": "cardio machine", "pattern": "cardio",
               "mechanic": "compound", "category": "cardio", "difficulty": "beginner"},
              {"id": "abdominals-stretch-variation-one",
               "displayName": "Abdominals Stretch Variation One",
               "primaryMuscles": ["abdominals"], "secondaryMuscles": [],
               "equipment": "bodyweight", "pattern": "stretch", "force": "static",
               "mechanic": "isolation", "category": "stretching", "difficulty": "beginner"}
            ]
            """
        let exercises = try JSONDecoder().decode([Exercise].self, from: Data(json.utf8))
        return ExerciseCatalog(exercises: exercises, version: 5)
    }

    private func logged(
        _ index: Int, reps: Int, seconds: Int? = nil, distance: Distance? = nil,
        load: Mass? = nil, warmup: Bool = false
    ) -> SnapshotLoggedSet {
        SnapshotLoggedSet(
            setIndex: index, load: load, reps: reps, durationSeconds: seconds,
            distance: distance, rpe: nil, isCompleted: true, isWarmup: warmup,
            completedAt: daysAgo(2))
    }

    private func performed(
        _ id: String, _ name: String, order: Int, target: String,
        sets: [SnapshotLoggedSet]
    ) -> SnapshotPlannedExercise {
        SnapshotPlannedExercise(
            exerciseID: ExerciseID(rawValue: id), displayName: name, order: order,
            targetSets: sets.count, repRange: target, suggestedLoad: nil,
            restSeconds: nil, tempo: nil, notes: nil,
            prescribedSets: SetPrescription.everySet(
                stated: [], count: sets.count, repRange: target,
                suggestedLoad: nil, intensity: nil),
            loggedSets: sets)
    }

    /// One day: three working sets of bench, forty minutes on the bike over
    /// fifteen kilometres, and two held stretches.
    private func mixedSnapshot() -> TrainingSnapshot {
        let bar = Mass(value: 225, unit: .pounds)
        let day = SnapshotDay(
            weekday: .monday, focus: "Push and conditioning", durationMinutes: 75,
            completedAt: daysAgo(2),
            exercises: [
                performed(
                    "barbell-bench-press", "Barbell Bench Press", order: 0, target: "5",
                    sets: [
                        logged(0, reps: 5, load: Mass(value: 135, unit: .pounds), warmup: true),
                        logged(1, reps: 5, load: bar),
                        logged(2, reps: 5, load: bar),
                        logged(3, reps: 4, load: bar),
                    ]),
                performed(
                    "assault-bike", "Assault Bike", order: 1, target: "40 minutes",
                    sets: [
                        logged(
                            0, reps: 0, seconds: 2400,
                            distance: Distance(value: 15, unit: .kilometres))
                    ]),
                performed(
                    "abdominals-stretch-variation-one", "Abdominals Stretch Variation One",
                    order: 2, target: "30 seconds",
                    sets: [logged(0, reps: 0, seconds: 30), logged(1, reps: 0, seconds: 30)]),
            ])
        let plan = SnapshotPlan(
            title: "Mixed block", goal: "Bench and conditioning", startDate: daysAgo(10),
            weekCount: 1, completedAt: nil, catalogVersion: 5, weekdays: [.monday],
            durationMinutes: 75,
            weeks: [SnapshotWeek(ordinal: 1, label: "", isDeload: false, days: [day])])
        return fixtureSnapshot(plans: [plan])
    }

    private func volume() throws -> JSONValue {
        let outcome = try makeRunner(
            documents: InMemoryDocuments(snapshot: mixedSnapshot()),
            catalog: try mixedCatalog()
        ).call(ToolCatalog.volumeByMuscle, arguments: ["weeks": 4])
        return try #require(outcome.report)
    }

    private func muscles(in report: JSONValue) throws -> [String] {
        try #require(report["muscles"]?.arrayValue).compactMap { $0["muscle"]?.stringValue }
    }

    private func excludedCategory(_ name: String, in report: JSONValue) throws -> JSONValue {
        let categories = try #require(report["excluded"]?["categories"]?.arrayValue)
        return try #require(categories.first { $0["category"] == .string(name) })
    }

    // MARK: - What the totals count

    @Test("Cycling is not quadriceps volume")
    func cardioIsNotMuscleVolume() throws {
        #expect(!(try muscles(in: try volume()).contains("quadriceps")))
    }

    @Test("A held stretch is not abdominal volume")
    func stretchingIsNotMuscleVolume() throws {
        #expect(!(try muscles(in: try volume()).contains("abdominals")))
    }

    @Test("The lifting in the same session is counted in full")
    func resistanceStillCounts() throws {
        let report = try volume()
        let muscles = try #require(report["muscles"]?.arrayValue)
        let chest = try #require(muscles.first { $0["muscle"] == .string("chest") })

        #expect(chest["primarySets"] == 3)
        #expect(chest["primaryReps"] == 14)
    }

    // MARK: - What happens to the work that is not counted

    @Test("Excluded sets are disclosed rather than dropped")
    func excludedWorkIsReported() throws {
        let report = try volume()

        #expect(report["excluded"]?["sets"] == 3)
        #expect(report["unattributed"]?["sets"] == 0)
    }

    @Test("The excluded work is reported by category, in the units it was performed in")
    func excludedWorkKeepsItsUnits() throws {
        let report = try volume()
        let cardio = try excludedCategory("cardio", in: report)
        let stretching = try excludedCategory("stretching", in: report)

        #expect(cardio["sets"] == 1)
        #expect(cardio["seconds"] == 2400)
        #expect(cardio["reps"] == 0)
        #expect(cardio["distance"]?.arrayValue == [["unit": "km", "value": 15.0]])
        #expect(cardio["exerciseIDs"] == ["assault-bike"])

        #expect(stretching["sets"] == 2)
        #expect(stretching["seconds"] == 60)
        #expect(stretching["exerciseIDs"] == ["abdominals-stretch-variation-one"])
    }

    @Test("Nothing excluded reads as nothing excluded, not as an absent section")
    func nothingExcludedIsStated() throws {
        let outcome = try makeRunner(documents: InMemoryDocuments(snapshot: fixtureSnapshot()))
            .call(ToolCatalog.volumeByMuscle, arguments: ["weeks": 4])
        let report = try #require(outcome.report)

        #expect(report["excluded"]?["sets"] == 0)
        #expect(report["excluded"]?["categories"] == .array([]))
        #expect(report["excluded"]?["note"]?.stringValue?.isEmpty == false)
    }

    // MARK: - What the report says it counts

    @Test("The counting rule says the totals are resistance training")
    func countingRuleStatesTheFilter() throws {
        let counts = try #require(try volume()["counts"]?.stringValue).lowercased()

        #expect(counts.contains("resistance"))
        // Named from the same list the filter applies, so the rule cannot drift
        // from what is actually counted.
        for category in ExerciseCategory.resistance {
            #expect(counts.contains(category.rawValue))
        }
    }

    @Test("The tool says so before it is called, too")
    func toolDescriptionStatesTheFilter() throws {
        #expect(ToolCatalog.volumeByMuscleDefinition.description.contains("resistance"))
        #expect(ToolCatalog.volumeByMuscleDefinition.description.contains("excluded"))
    }
}
