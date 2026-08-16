import Foundation
import Testing
@testable import LiftingKit

/// The bytes of `snapshot.json`, read the way its consumer reads them.
///
/// Encoding a snapshot and decoding it back proves the encoder and the decoder
/// agree with each other — not that they agree with anyone else. Rename a
/// coding key on both halves at once and that round trip stays green while
/// every per-set prescription becomes invisible to the reader on the other side
/// of the file. So these tests do the two things a round trip cannot: they read
/// the encoded JSON as untyped values and name the keys that must be there, and
/// they decode a document written by hand rather than by the encoder.
@Suite("Snapshot wire shape")
struct SnapshotWireShapeTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    /// A day earlier than `instant`: a plan is written before it arrives.
    private static let written = Date(timeIntervalSince1970: 1_699_913_600)

    /// One plan with a per-set prescription, a stated effort, a counted set and
    /// a held one — everything whose wire shape a reader depends on.
    private func snapshot() -> TrainingSnapshot {
        let exercise = SnapshotPlannedExercise(
            exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
            displayName: "Barbell Bench Press", order: 0, targetSets: 2,
            repRange: "5", suggestedLoad: Mass(value: 100, unit: .kilograms),
            restSeconds: 180,
            intensity: IntensityTarget(scale: .rpe, value: "8-9"),
            tempo: "3-0-1-0", notes: nil,
            prescribedSets: [
                SetPrescription(
                    repRange: "5", suggestedLoad: Mass(value: 100, unit: .kilograms),
                    intensity: IntensityTarget(scale: .rpe, value: "8")),
                SetPrescription(
                    repRange: "AMRAP", suggestedLoad: Mass(value: 80, unit: .kilograms),
                    intensity: IntensityTarget(scale: .repsInReserve, value: "0"),
                    notes: "Back-off set"),
            ],
            loggedSets: [
                SnapshotLoggedSet(
                    setIndex: 0, load: Mass(value: 100, unit: .kilograms), reps: 5,
                    rpe: 8, isCompleted: true, isWarmup: false, completedAt: Self.instant),
                SnapshotLoggedSet(
                    setIndex: 1, load: nil, reps: 0, durationSeconds: 34,
                    rpe: nil, isCompleted: true, isWarmup: false, completedAt: Self.instant),
                SnapshotLoggedSet(
                    setIndex: 2, load: Mass(value: 32, unit: .kilograms), reps: 0,
                    distance: Distance(value: 40, unit: .metres),
                    rpe: nil, isCompleted: true, isWarmup: false, completedAt: Self.instant),
            ]
        )
        return TrainingSnapshot(
            catalogVersion: 5, generatedAt: Self.instant,
            plans: [SnapshotPlan(
                title: "Block", goal: "", notes: "Three heavy weeks, then a deload.",
                startDate: Self.instant, generatedAt: Self.written, weekCount: 1,
                completedAt: nil, catalogVersion: 5, weekdays: [.monday],
                durationMinutes: nil,
                weeks: [SnapshotWeek(
                    ordinal: 1, label: "", isDeload: false,
                    days: [SnapshotDay(
                        weekday: .monday, focus: "Push", durationMinutes: nil,
                        completedAt: nil, exercises: [exercise])])])]
        )
    }

    /// The encoded block as untyped JSON, which is all a consumer has.
    private func encodedPlan() throws -> [String: Any] {
        let data = try TrainingSnapshot.makeEncoder().encode(snapshot())
        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let plans = try #require(root["plans"] as? [[String: Any]])
        return try #require(plans.first)
    }

    /// The encoded document as untyped JSON, which is all a consumer has.
    private func encodedExercise() throws -> [String: Any] {
        let plans = try [encodedPlan()]
        let weeks = try #require(plans.first?["weeks"] as? [[String: Any]])
        let days = try #require(weeks.first?["days"] as? [[String: Any]])
        let exercises = try #require(days.first?["exercises"] as? [[String: Any]])
        return try #require(exercises.first)
    }

    // MARK: - The keys a reader reads

    @Test("The coach's note is written under 'notes', beside the block's title")
    func planNoteIsOnTheWire() throws {
        let plan = try encodedPlan()

        #expect(plan["notes"] as? String == "Three heavy weeks, then a deload.")
        #expect(plan["title"] as? String == "Block")
    }

    @Test("When a plan was written is on the wire beside when it started")
    func planWrittenDateIsOnTheWire() throws {
        let plan = try encodedPlan()

        #expect(plan["generatedAt"] as? String == "2023-11-13T22:13:20Z")
        #expect(plan["startDate"] as? String == "2023-11-14T22:13:20Z")
    }

    @Test("A block with no note writes no key rather than an empty string")
    func absentNoteWritesNoKey() throws {
        let bare = SnapshotPlan(
            title: "", goal: "", startDate: Self.instant, weekCount: nil,
            completedAt: nil, catalogVersion: nil, weekdays: [], durationMinutes: nil,
            weeks: [])
        let snapshot = TrainingSnapshot(
            catalogVersion: 5, generatedAt: Self.instant, plans: [bare])
        let data = try TrainingSnapshot.makeEncoder().encode(snapshot)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let plan = try #require((root["plans"] as? [[String: Any]])?.first)

        #expect(plan["notes"] == nil, "he wrote none; an empty string would say he wrote one")
        #expect(plan["generatedAt"] == nil)
    }

    @Test("A prescribed set is written under 'prescribedSets', set by set")
    func prescribedSetsAreOnTheWire() throws {
        let sets = try #require(try encodedExercise()["prescribedSets"] as? [[String: Any]])

        #expect(sets.count == 2)
        #expect(sets.first?["repRange"] as? String == "5")
        #expect(sets.last?["repRange"] as? String == "AMRAP")
        #expect(sets.last?["notes"] as? String == "Back-off set")
        let load = try #require(sets.last?["suggestedLoad"] as? [String: Any])
        #expect(load["value"] as? Double == 80)
        #expect(load["unit"] as? String == "kg")
    }

    @Test("A prescribed effort is written as a scale and a value")
    func intensityIsOnTheWire() throws {
        let exercise = try encodedExercise()
        let intensity = try #require(exercise["intensity"] as? [String: Any])
        #expect(intensity["scale"] as? String == "rpe")
        #expect(intensity["value"] as? String == "8-9")

        let sets = try #require(exercise["prescribedSets"] as? [[String: Any]])
        let perSet = try #require(sets.last?["intensity"] as? [String: Any])
        #expect(perSet["scale"] as? String == "rir")
        #expect(perSet["value"] as? String == "0")
    }

    @Test("A held set is written under 'durationSeconds' and reports no reps")
    func heldSetIsOnTheWire() throws {
        let sets = try #require(try encodedExercise()["loggedSets"] as? [[String: Any]])
        let held = try #require(sets.first { $0["setIndex"] as? Int == 1 })

        #expect(held["durationSeconds"] as? Int == 34)
        #expect(held["reps"] as? Int == 0, "seconds are not repetitions")
        #expect(held["distance"] == nil, "a hold went nowhere")
    }

    @Test("A carried set is written under 'distance' as a number and its unit")
    func carriedSetIsOnTheWire() throws {
        let sets = try #require(try encodedExercise()["loggedSets"] as? [[String: Any]])
        let carried = try #require(sets.first { $0["setIndex"] as? Int == 2 })
        let distance = try #require(carried["distance"] as? [String: Any])

        #expect(distance["value"] as? Double == 40)
        #expect(distance["unit"] as? String == "m", "the unit travels with the number")
        #expect(carried["reps"] as? Int == 0, "metres are not repetitions")
        #expect(carried["durationSeconds"] == nil, "nor were they seconds")
    }

    @Test("A counted set writes no duration and no distance rather than zeroes")
    func countedSetWritesNoDuration() throws {
        let sets = try #require(try encodedExercise()["loggedSets"] as? [[String: Any]])
        let counted = try #require(sets.first)

        #expect(counted["reps"] as? Int == 5)
        #expect(
            counted["durationSeconds"] == nil,
            "a set that was not timed did not last no time")
        #expect(
            counted["distance"] == nil,
            "a set that was not carried did not travel no distance")
    }

    // MARK: - A document written by hand, not by the encoder

    /// Written out the way a reader would meet it, including the two shapes no
    /// round trip could vouch for: a listed prescription and a held set.
    private static let handWritten = """
        {
          "version": 1,
          "catalogVersion": 5,
          "generatedAt": "2023-11-14T22:13:20Z",
          "plans": [{
            "title": "Block", "goal": "", "startDate": "2023-11-14T22:13:20Z",
            "weekCount": 1, "catalogVersion": 5, "weekdays": [2], "weeks": [{
              "ordinal": 1, "label": "", "isDeload": false, "days": [{
                "weekday": 2, "focus": "Push", "exercises": [{
                  "exerciseID": "barbell-bench-press", "displayName": "Bench",
                  "order": 0, "targetSets": 2, "repRange": "30 seconds",
                  "restSeconds": 90,
                  "intensity": {"scale": "rpe", "value": "8-9"},
                  "prescribedSets": [
                    {"repRange": "30 seconds",
                     "intensity": {"scale": "rpe", "value": "8"}},
                    {"repRange": "AMRAP",
                     "suggestedLoad": {"value": 80, "unit": "kg"},
                     "notes": "Back-off set"}
                  ],
                  "loggedSets": [
                    {"setIndex": 0, "reps": 0, "durationSeconds": 34,
                     "isCompleted": true, "isWarmup": false,
                     "completedAt": "2023-11-14T22:13:20Z"},
                    {"setIndex": 1, "reps": 9,
                     "load": {"value": 80, "unit": "kg"},
                     "isCompleted": true, "isWarmup": false,
                     "completedAt": "2023-11-14T22:13:20Z"},
                    {"setIndex": 2, "reps": 0,
                     "distance": {"value": 40, "unit": "m"},
                     "isCompleted": true, "isWarmup": false,
                     "completedAt": "2023-11-14T22:13:20Z"}
                  ]
                }]
              }]
            }]
          }]
        }
        """

    private func decodedExercise() throws -> SnapshotPlannedExercise {
        let decoded = try TrainingSnapshot.makeDecoder()
            .decode(TrainingSnapshot.self, from: Data(Self.handWritten.utf8))
        let plan = try #require(decoded.plans.first)
        let week = try #require(plan.weeks.first)
        let day = try #require(week.days.first)
        return try #require(day.exercises.first)
    }

    @Test("A hand-written snapshot's per-set prescription decodes in full")
    func handWrittenPrescriptionDecodes() throws {
        let exercise = try decodedExercise()

        #expect(exercise.prescribedSets.count == 2)
        #expect(exercise.prescribedSets.first?.repRange == "30 seconds")
        #expect(exercise.prescribedSets.first?.intensity
            == IntensityTarget(scale: .rpe, value: "8"))
        #expect(exercise.prescribedSets.last?.suggestedLoad?.value == 80)
        #expect(exercise.prescribedSets.last?.notes == "Back-off set")
        #expect(exercise.intensity == IntensityTarget(scale: .rpe, value: "8-9"))
    }

    @Test("A hand-written held set decodes as a duration, not as reps")
    func handWrittenHeldSetDecodes() throws {
        let sets = try decodedExercise().loggedSets

        #expect(sets.first?.durationSeconds == 34)
        #expect(sets.first?.reps == 0)
        #expect(sets.first?.distance == nil)
        #expect(sets.dropFirst().first?.durationSeconds == nil)
        #expect(sets.dropFirst().first?.reps == 9)
    }

    @Test("A hand-written carried set decodes as a distance in the unit it names")
    func handWrittenCarriedSetDecodes() throws {
        let carried = try #require(try decodedExercise().loggedSets.last)

        #expect(carried.distance == Distance(value: 40, unit: .metres))
        #expect(carried.reps == 0)
        #expect(carried.durationSeconds == nil)
    }

    @Test("A hand-written block's note and written date decode as stated")
    func handWrittenPlanNoteDecodes() throws {
        let json = Self.handWritten.replacingOccurrences(
            of: "\"title\": \"Block\", \"goal\": \"\",",
            with: "\"title\": \"Block\", \"goal\": \"\", \"notes\": \"Eat.\", "
                + "\"generatedAt\": \"2023-11-13T22:13:20Z\",")
        let decoded = try TrainingSnapshot.makeDecoder()
            .decode(TrainingSnapshot.self, from: Data(json.utf8))

        #expect(decoded.plans.first?.notes == "Eat.")
        #expect(decoded.plans.first?.generatedAt == Self.written)
    }

    @Test("A snapshot written before a block could carry a note reads as having none")
    func olderSnapshotHasNoNote() throws {
        let decoded = try TrainingSnapshot.makeDecoder()
            .decode(TrainingSnapshot.self, from: Data(Self.handWritten.utf8))
        let plan = try #require(decoded.plans.first)

        #expect(plan.notes == nil)
        #expect(plan.generatedAt == nil)
        #expect(plan.title == "Block", "everything it did state still reads")
    }

    @Test("A snapshot written before durations or distances existed reads as having none")
    func olderSnapshotHasNeither() throws {
        let json = Self.handWritten
            .replacingOccurrences(of: "\"reps\": 0, \"durationSeconds\": 34", with: "\"reps\": 0")
            .replacingOccurrences(
                of: "\"distance\": {\"value\": 40, \"unit\": \"m\"},", with: "")
        let decoded = try TrainingSnapshot.makeDecoder()
            .decode(TrainingSnapshot.self, from: Data(json.utf8))
        let exercise = try #require(
            decoded.plans.first?.weeks.first?.days.first?.exercises.first)

        #expect(exercise.loggedSets.first?.durationSeconds == nil)
        #expect(exercise.loggedSets.first?.reps == 0)
        #expect(exercise.loggedSets.allSatisfy { $0.distance == nil })
    }
}
