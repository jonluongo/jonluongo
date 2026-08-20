import Foundation
import Testing
@testable import LiftingKit

@Suite("Training snapshot")
struct TrainingSnapshotTests {

    // MARK: - A snapshot from a build this one cannot read

    /// The shape a v2 reader would otherwise take in silently: a version it has
    /// never seen, and the training under a key it does not know.
    private static func laterSnapshot(version: Int) -> Data {
        Data("""
            {
              "version": \(version),
              "catalogVersion": 5,
              "generatedAt": "2023-11-14T22:13:20Z",
              "routines": [{ "everything": "the lifter has ever trained" }]
            }
            """.utf8)
    }

    @Test("A snapshot from a later build is refused, naming both versions")
    func laterVersionIsRefused() throws {
        let error = #expect(throws: DocumentRefusal.self) {
            try TrainingSnapshot.makeDecoder().decode(
                TrainingSnapshot.self, from: Self.laterSnapshot(version: 99))
        }

        #expect(error == .snapshotVersionMismatch(99, understood: TrainingSnapshot.currentVersion))
    }

    @Test("The refusal says what would otherwise be reported, and how to fix it")
    func refusalNamesTheFailureAndTheRemedy() {
        let message = DocumentRefusal
            .snapshotVersionMismatch(3, understood: 2).errorDescription ?? ""

        #expect(message.contains("version 3"))
        #expect(message.contains("version 2"))
        // The point of refusing rather than reading: the alternative is a
        // well-formed report of a lifter who has done nothing.
        #expect(message.contains("trained less than he has"))
        #expect(message.contains("Rebuild the MCP server"))
    }

    @Test("Refusing comes before anything else is held against the document")
    func versionIsCheckedFirst() throws {
        // The fixture states no `generatedAt`, which is required. A reader that
        // checked keys first would report a missing timestamp — true, useless,
        // and it would send whoever read it looking in the wrong place.
        let stated = Data("""
            {"version": 99, "catalogVersion": 5}
            """.utf8)

        let error = #expect(throws: DocumentRefusal.self) {
            try TrainingSnapshot.makeDecoder().decode(TrainingSnapshot.self, from: stated)
        }

        #expect(error == .snapshotVersionMismatch(99, understood: TrainingSnapshot.currentVersion))
    }

    @Test("A snapshot this build writes reads; one written in any other version does not")
    func onlyTheCurrentVersionReads() throws {
        let current = try TrainingSnapshot.makeEncoder().encode(snapshot())
        #expect(throws: Never.self) {
            try TrainingSnapshot.makeDecoder().decode(TrainingSnapshot.self, from: current)
        }

        // Older is refused as well as newer, which the two write formats do not
        // do. A plan is an archive and must be read forever; a snapshot is a
        // cache the phone rewrites whenever the record changes, so an old one is
        // a stale file rather than history — and reading it as though its
        // sections were merely absent would report a lifter who has never
        // trained.
        let older = Data("""
            {"version": 2, "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z"}
            """.utf8)
        #expect(throws: DocumentRefusal.snapshotVersionMismatch(
            2, understood: TrainingSnapshot.currentVersion)
        ) {
            try TrainingSnapshot.makeDecoder().decode(TrainingSnapshot.self, from: older)
        }
    }

    // MARK: - Fixtures

    /// A fixed instant on a second boundary. ISO 8601 encodes whole seconds,
    /// so a date built this way survives a round trip exactly and whole-value
    /// equality is a fair assertion.
    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)

    private static let routineID = UUID(uuidString: "3E7F7E2E-2B47-4C51-9E58-52C1D1F0A0B1")!

    private func loggedSet(load: Mass?) -> LoggedSetRecord {
        LoggedSetRecord(
            routineID: Self.routineID, blockOrdinal: 1, weekday: .monday, exerciseOrder: 0,
            exerciseID: ExerciseID(rawValue: "barbell-bench-press"), setIndex: 0,
            isWarmup: false, isCompleted: true, completedAt: Self.instant,
            load: load, reps: 5
        )
    }

    private func snapshot(
        load: Mass? = Mass(value: 135, unit: .pounds),
        restSeconds: Int? = 180,
        avoidedPatterns: [MovementPattern] = [.hinge],
        availableEquipment: [EquipmentType] = [.barbell]
    ) -> TrainingSnapshot {
        let exercise = PlanDocumentExercise(
            exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
            displayName: "Barbell Bench Press", sets: 3, repRange: "5",
            restSeconds: restSeconds,
            suggestedLoad: Mass(value: 100, unit: .kilograms),
            tempo: "3-0-1-0", notes: "Pause the last rep"
        )
        let routine = SnapshotRoutine(
            document: PlanDocument(
                id: Self.routineID, catalogVersion: 5, generatedAt: Self.instant,
                title: "Strength block", goal: "Bigger bench", durationMinutes: 60,
                blocks: [PlanDocumentBlock(
                    label: "Accumulation", isDeload: false,
                    days: [PlanDocumentDay(
                        weekday: .monday, focus: "Push", durationMinutes: 60,
                        exercises: [exercise])])]),
            startDate: Self.instant,
            sessions: [SnapshotSession(
                blockOrdinal: 1, weekday: .monday, completedAt: Self.instant)]
        )
        let profile = SnapshotProfile(
            displayUnit: .pounds, experience: .intermediate,
            availableEquipment: availableEquipment, goal: "Get stronger",
            constraints: "Left shoulder hurts overhead",
            bodyweight: Mass(value: 182, unit: .pounds),
            avoidedPatterns: avoidedPatterns,
            avoidedExercises: [ExerciseID(rawValue: "barbell-upright-row")],
            preferredWeekdays: [.monday, .thursday], preferredDurationMinutes: 60,
            statedAt: ["goal": Date(timeIntervalSince1970: 1_700_000_000)]
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
            routines: [routine],
            log: [loggedSet(load: load)]
        )
    }

    private func roundTrip(_ snapshot: TrainingSnapshot) throws -> TrainingSnapshot {
        let data = try TrainingSnapshot.makeEncoder().encode(snapshot)
        return try TrainingSnapshot.makeDecoder().decode(TrainingSnapshot.self, from: data)
    }

    private func firstLoggedSet(in snapshot: TrainingSnapshot) throws -> LoggedSetRecord {
        try #require(snapshot.log.first)
    }

    /// The one movement the fixture prescribes, read out of the document the
    /// routine carries.
    private func firstExercise(in snapshot: TrainingSnapshot) throws -> PlanDocumentExercise {
        let routine = try #require(snapshot.routines.first)
        let week = try #require(routine.document.blocks.first)
        let day = try #require(week.days.first)
        return try #require(day.entries.flatMap(\.exercises).first)
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
        let exercise = try firstExercise(in: decoded)

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
          "version": 5,
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
        #expect(decoded.routines.isEmpty)
        #expect(decoded.log.isEmpty)
        #expect(decoded == empty)
    }

    @Test("Absent sections decode as empty rather than failing")
    func absentSectionsDecodeAsEmpty() throws {
        let json = """
        {"version": 5, "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z"}
        """
        let decoded = try TrainingSnapshot.makeDecoder()
            .decode(TrainingSnapshot.self, from: Data(json.utf8))

        #expect(decoded.profile == nil)
        #expect(decoded.routines.isEmpty)
        #expect(decoded.log.isEmpty)
        #expect(decoded.generatedAt == Self.instant)
    }

    @Test("A lifter who has stated nothing about himself reads as unknown, not as a default")
    func unstatedProfileFactsAreAbsent() throws {
        // The whole point of the optionals: the app asks him nothing, so an
        // untouched profile must not tell a reader "full gym, intermediate".
        let blank = SnapshotProfile(
            displayUnit: .pounds, experience: nil,
            availableEquipment: nil, goal: "", constraints: "", bodyweight: nil,
            avoidedPatterns: [], avoidedExercises: [], preferredWeekdays: [],
            preferredDurationMinutes: nil, statedAt: ["goal": Date(timeIntervalSince1970: 1_700_000_000)]
        )
        let decoded = try roundTrip(
            TrainingSnapshot(catalogVersion: 5, generatedAt: Self.instant, profile: blank)
        )
        let profile = try #require(decoded.profile)

        #expect(profile.experience == nil)
        // Not an empty list: "he can perform nothing" is a far stronger claim
        // than "nobody has said what he has".
        #expect(profile.availableEquipment == nil)
        #expect(profile == blank)
    }

    @Test("An unknown equipment access writes no key rather than a stated default")
    func unstatedEquipmentWritesNoKey() throws {
        let blank = SnapshotProfile(
            displayUnit: .pounds, experience: nil,
            availableEquipment: nil, goal: "", constraints: "", bodyweight: nil,
            avoidedPatterns: [], avoidedExercises: [], preferredWeekdays: [],
            preferredDurationMinutes: nil, statedAt: ["goal": Date(timeIntervalSince1970: 1_700_000_000)]
        )
        let data = try TrainingSnapshot.makeEncoder().encode(
            TrainingSnapshot(catalogVersion: 5, generatedAt: Self.instant, profile: blank))
        let json = String(decoding: data, as: UTF8.self)

        #expect(!json.contains("equipmentAccess"))
        #expect(!json.contains("availableEquipment"))
        #expect(!json.contains("experience"))
    }

    @Test("A profile with no dates on it reads as a profile with no dates")
    func aProfileWithoutStatedDatesDecodes() throws {
        // Every install predating the phone keeping dates has exactly this, and
        // so does a snapshot written by hand. The facts are there; only the
        // record of when they were stated is missing.
        let data = Data(        """
        {
          "version": 5, "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z",
          "profile": {
            "displayUnit": "lb", "goal": "Bench 225", "constraints": "",
            "avoidedPatterns": [], "avoidedExercises": [], "preferredWeekdays": []
          }
        }
        """
       .utf8)

        let snapshot = try TrainingSnapshot.makeDecoder()
            .decode(TrainingSnapshot.self, from: data)

        #expect(snapshot.profile?.goal == "Bench 225")
        #expect(snapshot.profile?.statedAt.isEmpty == true)
    }

    @Test("A profile written before these facts were known decodes as not knowing them")
    func profileWithoutStatedFactsDecodes() throws {
        let json = """
        {
          "version": 5,
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
        #expect(profile.availableEquipment == nil)
        #expect(profile.displayUnit == .pounds)
    }

    @Test("An unprescribed rest stays absent rather than becoming a number")
    func absentRestStaysAbsent() throws {
        let decoded = try roundTrip(snapshot(restSeconds: nil))
        #expect(try firstExercise(in: decoded).restSeconds == nil)
    }

    @Test("A bodyweight set has no load rather than a zero load")
    func bodyweightSetHasNoLoad() throws {
        let decoded = try roundTrip(snapshot(load: nil))
        let set = try firstLoggedSet(in: decoded)
        #expect(set.load == nil)
        #expect(set.reps == 5)
    }
}
