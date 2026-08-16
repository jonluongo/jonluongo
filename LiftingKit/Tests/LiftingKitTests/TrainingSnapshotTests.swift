import Foundation
import Testing
@testable import LiftingKit

@Suite("Training snapshot")
struct TrainingSnapshotTests {

    // MARK: - Fixtures

    /// A fixed instant on a second boundary. ISO 8601 encodes whole seconds,
    /// so a date built this way survives a round trip exactly and whole-value
    /// equality is a fair assertion.
    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)

    private func loggedSet(load: Mass?) -> SnapshotLoggedSet {
        SnapshotLoggedSet(
            setIndex: 0, load: load, reps: 5, rpe: 8.5,
            isCompleted: true, isWarmup: false, completedAt: Self.instant
        )
    }

    private func snapshot(
        load: Mass? = Mass(value: 135, unit: .pounds),
        restSeconds: Int? = 180,
        avoidedPatterns: [MovementPattern] = [.hinge],
        availableEquipment: [EquipmentType] = [.barbell]
    ) -> TrainingSnapshot {
        let exercise = SnapshotPlannedExercise(
            exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
            displayName: "Barbell Bench Press",
            order: 0, targetSets: 3, repRange: "5",
            suggestedLoad: Mass(value: 100, unit: .kilograms),
            restSeconds: restSeconds, tempo: "3-0-1-0", notes: "Pause the last rep",
            loggedSets: [loggedSet(load: load)]
        )
        let day = SnapshotDay(
            weekday: .monday, focus: "Push", durationMinutes: 60,
            completedAt: Self.instant, exercises: [exercise]
        )
        let week = SnapshotWeek(ordinal: 1, label: "Accumulation", isDeload: false, days: [day])
        let plan = SnapshotPlan(
            title: "Strength block", goal: "Bigger bench", startDate: Self.instant,
            weekCount: 4, completedAt: nil, catalogVersion: 5,
            weekdays: [.monday, .thursday], durationMinutes: 60, weeks: [week]
        )
        let profile = SnapshotProfile(
            displayUnit: .pounds, experience: .intermediate, equipmentAccess: .fullGym,
            availableEquipment: availableEquipment, goal: "Get stronger",
            constraints: "Left shoulder hurts overhead",
            bodyweight: Mass(value: 182, unit: .pounds),
            avoidedPatterns: avoidedPatterns,
            avoidedExercises: [ExerciseID(rawValue: "barbell-upright-row")],
            preferredWeekdays: [.monday, .thursday], preferredDurationMinutes: 60,
            updatedAt: Self.instant
        )
        return TrainingSnapshot(
            catalogVersion: 5, generatedAt: Self.instant, profile: profile,
            bodyMetrics: [SnapshotBodyMetric(
                date: Self.instant, bodyweight: Mass(value: 182, unit: .pounds)
            )],
            baselines: [SnapshotBaseline(
                exerciseID: ExerciseID(rawValue: "barbell-back-squat"),
                load: Mass(value: 225, unit: .pounds), reps: 5, recordedAt: Self.instant
            )],
            plans: [plan]
        )
    }

    private func roundTrip(_ snapshot: TrainingSnapshot) throws -> TrainingSnapshot {
        let data = try TrainingSnapshot.makeEncoder().encode(snapshot)
        return try TrainingSnapshot.makeDecoder().decode(TrainingSnapshot.self, from: data)
    }

    private func firstLoggedSet(in snapshot: TrainingSnapshot) throws -> SnapshotLoggedSet {
        let plan = try #require(snapshot.plans.first)
        let week = try #require(plan.weeks.first)
        let day = try #require(week.days.first)
        let exercise = try #require(day.exercises.first)
        return try #require(exercise.loggedSets.first)
    }

    // MARK: - Round trip

    @Test("A full snapshot survives encoding and decoding unchanged")
    func fullSnapshotRoundTrips() throws {
        let original = snapshot()
        #expect(try roundTrip(original) == original)
    }

    @Test("A snapshot carries its own version and the catalog version it was made against")
    func carriesBothVersions() throws {
        let decoded = try roundTrip(snapshot())
        #expect(decoded.version == TrainingSnapshot.currentVersion)
        #expect(decoded.catalogVersion == 5)
    }

    // MARK: - Mass is not canonicalized

    @Test("A logged set keeps the unit it was entered in rather than being canonicalized")
    func loggedSetKeepsEnteredUnit() throws {
        let decoded = try roundTrip(snapshot(load: Mass(value: 135, unit: .pounds)))
        let load = try #require(try firstLoggedSet(in: decoded).load)

        #expect(load.unit == .pounds)
        #expect(load.value == 135)
        // `Mass` compares exactly on representation, so this fails the moment
        // anything in the pipeline rewrites pounds into their kilogram value.
        #expect(load == Mass(value: 135, unit: .pounds))
        #expect(load != Mass(value: 135, unit: .pounds).converted(to: .kilograms))
    }

    @Test("A kilogram load stays kilograms and is not rewritten as pounds")
    func kilogramLoadStaysKilograms() throws {
        let decoded = try roundTrip(snapshot(load: Mass(value: 100, unit: .kilograms)))
        let load = try #require(try firstLoggedSet(in: decoded).load)

        #expect(load == Mass(value: 100, unit: .kilograms))
        #expect(load != Mass(value: 100, unit: .kilograms).converted(to: .pounds))
    }

    @Test("Every weight in a snapshot keeps its own unit, not one shared unit")
    func weightsKeepIndependentUnits() throws {
        let decoded = try roundTrip(snapshot(load: Mass(value: 135, unit: .pounds)))
        let exercise = try #require(decoded.plans.first?.weeks.first?.days.first?.exercises.first)

        // The set was logged in pounds and the prescription written in kilograms.
        #expect(try firstLoggedSet(in: decoded).load?.unit == .pounds)
        #expect(exercise.suggestedLoad == Mass(value: 100, unit: .kilograms))
        #expect(decoded.profile?.bodyweight == Mass(value: 182, unit: .pounds))
        #expect(decoded.baselines.first?.load == Mass(value: 225, unit: .pounds))
    }

    // MARK: - Unknown taxonomy values

    @Test("A movement pattern this build does not know survives a round trip intact")
    func unknownMovementPatternRoundTrips() throws {
        let unknown = MovementPattern(rawValue: "anti-rotation")
        #expect(!unknown.isKnown)

        let decoded = try roundTrip(snapshot(avoidedPatterns: [unknown, .hinge]))
        #expect(decoded.profile?.avoidedPatterns == [unknown, .hinge])
        #expect(decoded.profile?.avoidedPatterns.first?.rawValue == "anti-rotation")
    }

    @Test("An equipment type this build does not know survives a round trip intact")
    func unknownEquipmentTypeRoundTrips() throws {
        let unknown = EquipmentType(rawValue: "reverse hyper")
        #expect(!unknown.isKnown)

        let decoded = try roundTrip(snapshot(availableEquipment: [unknown, .barbell]))
        #expect(decoded.profile?.availableEquipment == [unknown, .barbell])
    }

    @Test("A snapshot written by a newer catalog decodes with its unknown values kept")
    func unknownValuesFromRawJSONDecode() throws {
        let json = """
        {
          "version": 1,
          "catalogVersion": 99,
          "generatedAt": "2023-11-14T22:13:20Z",
          "profile": {
            "displayUnit": "lb",
            "experience": "Intermediate",
            "equipmentAccess": "Full gym",
            "availableEquipment": ["barbell", "reverse hyper"],
            "goal": "",
            "constraints": "",
            "avoidedPatterns": ["anti-rotation"],
            "avoidedExercises": [],
            "preferredWeekdays": [],
            "updatedAt": "2023-11-14T22:13:20Z"
          }
        }
        """
        let decoded = try TrainingSnapshot.makeDecoder()
            .decode(TrainingSnapshot.self, from: Data(json.utf8))
        let profile = try #require(decoded.profile)

        #expect(profile.availableEquipment == [.barbell, EquipmentType(rawValue: "reverse hyper")])
        #expect(profile.avoidedPatterns == [MovementPattern(rawValue: "anti-rotation")])
        #expect(decoded.catalogVersion == 99)
    }

    // MARK: - Absence is normal

    @Test("A snapshot with no profile and nothing logged is valid, not an error")
    func emptySnapshotIsValid() throws {
        let empty = TrainingSnapshot(catalogVersion: 5, generatedAt: Self.instant)
        let decoded = try roundTrip(empty)

        #expect(decoded.profile == nil)
        #expect(decoded.bodyMetrics.isEmpty)
        #expect(decoded.baselines.isEmpty)
        #expect(decoded.plans.isEmpty)
        #expect(decoded == empty)
    }

    @Test("Absent sections decode as empty rather than failing")
    func absentSectionsDecodeAsEmpty() throws {
        let json = """
        {"version": 1, "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z"}
        """
        let decoded = try TrainingSnapshot.makeDecoder()
            .decode(TrainingSnapshot.self, from: Data(json.utf8))

        #expect(decoded.profile == nil)
        #expect(decoded.plans.isEmpty)
        #expect(decoded.generatedAt == Self.instant)
    }

    @Test("A lifter who has stated nothing about himself reads as unknown, not as a default")
    func unstatedProfileFactsAreAbsent() throws {
        // The whole point of the optionals: the app asks him nothing, so an
        // untouched profile must not tell a reader "full gym, intermediate".
        let blank = SnapshotProfile(
            displayUnit: .pounds, experience: nil, equipmentAccess: nil,
            availableEquipment: nil, goal: "", constraints: "", bodyweight: nil,
            avoidedPatterns: [], avoidedExercises: [], preferredWeekdays: [],
            preferredDurationMinutes: nil, updatedAt: Self.instant
        )
        let decoded = try roundTrip(
            TrainingSnapshot(catalogVersion: 5, generatedAt: Self.instant, profile: blank)
        )
        let profile = try #require(decoded.profile)

        #expect(profile.experience == nil)
        #expect(profile.equipmentAccess == nil)
        // Not an empty list: "he can perform nothing" is a far stronger claim
        // than "nobody has said what he has".
        #expect(profile.availableEquipment == nil)
        #expect(profile == blank)
    }

    @Test("An unknown equipment access writes no key rather than a stated default")
    func unstatedEquipmentWritesNoKey() throws {
        let blank = SnapshotProfile(
            displayUnit: .pounds, experience: nil, equipmentAccess: nil,
            availableEquipment: nil, goal: "", constraints: "", bodyweight: nil,
            avoidedPatterns: [], avoidedExercises: [], preferredWeekdays: [],
            preferredDurationMinutes: nil, updatedAt: Self.instant
        )
        let data = try TrainingSnapshot.makeEncoder().encode(
            TrainingSnapshot(catalogVersion: 5, generatedAt: Self.instant, profile: blank))
        let json = String(decoding: data, as: UTF8.self)

        #expect(!json.contains("equipmentAccess"))
        #expect(!json.contains("availableEquipment"))
        #expect(!json.contains("experience"))
    }

    @Test("A profile written before these facts were known decodes as not knowing them")
    func profileWithoutStatedFactsDecodes() throws {
        let json = """
        {
          "version": 1,
          "catalogVersion": 5,
          "generatedAt": "2023-11-14T22:13:20Z",
          "profile": {
            "displayUnit": "lb",
            "goal": "",
            "constraints": "",
            "avoidedPatterns": [],
            "avoidedExercises": [],
            "preferredWeekdays": [],
            "updatedAt": "2023-11-14T22:13:20Z"
          }
        }
        """
        let profile = try #require(
            try TrainingSnapshot.makeDecoder()
                .decode(TrainingSnapshot.self, from: Data(json.utf8)).profile)

        #expect(profile.experience == nil)
        #expect(profile.equipmentAccess == nil)
        #expect(profile.availableEquipment == nil)
        #expect(profile.displayUnit == .pounds)
    }

    @Test("An unprescribed rest stays absent rather than becoming a number")
    func absentRestStaysAbsent() throws {
        let decoded = try roundTrip(snapshot(restSeconds: nil))
        let exercise = try #require(decoded.plans.first?.weeks.first?.days.first?.exercises.first)
        #expect(exercise.restSeconds == nil)
    }

    @Test("A bodyweight set has no load rather than a zero load")
    func bodyweightSetHasNoLoad() throws {
        let decoded = try roundTrip(snapshot(load: nil))
        let set = try firstLoggedSet(in: decoded)
        #expect(set.load == nil)
        #expect(set.reps == 5)
    }
}
