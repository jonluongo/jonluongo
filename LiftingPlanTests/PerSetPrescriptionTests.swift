import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// A prescription whose sets differ, from the document Claude wrote all the way
/// to the store and back out in the snapshot.
///
/// The route is the point: a drop set that decodes but never reaches
/// `PlannedExercise`, or reaches it but is not reported back, is only half
/// built. Each test here follows one prescription the whole way.
@Suite("Per-set prescription through the app")
struct PerSetPrescriptionTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let bench = ExerciseID(rawValue: "barbell-bench-press")
    private static let squat = ExerciseID(rawValue: "barbell-squat")

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    private func catalog() throws -> ExerciseCatalog {
        try ExerciseCatalog.bundled()
    }

    private func document(_ exercises: [PlanDocumentExercise]) -> PlanDocument {
        PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant, title: "Block",
            days: [PlanDocumentDay(weekday: .monday, focus: "Push", exercises: exercises)]
        )
    }

    private func imported(_ exercises: [PlanDocumentExercise]) throws -> PlannedExercise {
        let context = try context()
        let plan = try PlanImporter.import(
            document(exercises), into: context, catalog: try catalog())
        let week = try #require(plan.orderedWeeks.first)
        let day = try #require(week.orderedDays.first)
        return try #require(day.orderedExercises.first)
    }

    private func kg(_ value: Double) -> Mass { Mass(value: value, unit: .kilograms) }

    // MARK: - Sets that differ reach the store

    @Test("A drop set reaches the store as four sets, the last one lighter")
    func dropSetReachesTheStore() throws {
        let exercise = try imported([
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench",
                sets: [
                    SetPrescription(),
                    SetPrescription(),
                    SetPrescription(),
                    SetPrescription(
                        repRange: "AMRAP", suggestedLoad: kg(70), notes: "Drop set"),
                ],
                repRange: "8", suggestedLoad: kg(100)
            )
        ])

        #expect(exercise.targetSets == 4)
        #expect(exercise.prescribedSets.map { $0.suggestedLoad?.value } == [100, 100, 100, 70])
        #expect(exercise.prescribedSets.map(\.repRange) == ["8", "8", "8", "AMRAP"])
        #expect(exercise.prescribedSets.last?.notes == "Drop set")
    }

    @Test("A ramping load reaches the store in the order it was written")
    func rampingLoadReachesTheStore() throws {
        let exercise = try imported([
            PlanDocumentExercise(
                exerciseID: Self.squat, displayName: "Squat",
                sets: [
                    SetPrescription(suggestedLoad: kg(60)),
                    SetPrescription(suggestedLoad: kg(70)),
                    SetPrescription(suggestedLoad: kg(80)),
                ],
                repRange: "5"
            )
        ])

        #expect(exercise.targetSets == 3)
        #expect(exercise.prescribedSets.map { $0.suggestedLoad?.value } == [60, 70, 80])
        #expect(exercise.prescribedSets.allSatisfy { $0.repRange == "5" })
    }

    @Test("A uniform prescription is stored as a count rather than as identical rows")
    func uniformIsStoredAsACount() throws {
        let exercise = try imported([
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench", sets: 3, repRange: "8-12")
        ])

        #expect(exercise.targetSets == 3)
        #expect(exercise.orderedStatedSets.isEmpty)
        #expect(exercise.prescribedSets.count == 3)
        #expect(exercise.prescribedSets.allSatisfy { $0.repRange == "8-12" })
    }

    // MARK: - Intensity reaches the store, on the scale it was written

    @Test("An RPE target reaches the store as an RPE target")
    func rpeReachesTheStore() throws {
        let exercise = try imported([
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench", sets: 3,
                intensity: IntensityTarget(scale: .rpe, value: "8"))
        ])

        #expect(exercise.intensity == IntensityTarget(scale: .rpe, value: "8"))
        #expect(exercise.prescribedSets.allSatisfy {
            $0.intensity == IntensityTarget(scale: .rpe, value: "8")
        })
    }

    @Test("A reps-in-reserve target and a percentage each keep their own scale")
    func otherScalesReachTheStore() throws {
        let rir = try imported([
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench", sets: 3,
                intensity: IntensityTarget(scale: .repsInReserve, value: "2"))
        ])
        let percent = try imported([
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench", sets: 3,
                intensity: IntensityTarget(scale: .percentOfOneRepMax, value: "80"))
        ])

        #expect(rir.intensity == IntensityTarget(scale: .repsInReserve, value: "2"))
        #expect(percent.intensity == IntensityTarget(scale: .percentOfOneRepMax, value: "80"))
    }

    @Test("An exercise with no intensity target has none after import")
    func absentIntensityStaysAbsent() throws {
        let exercise = try imported([
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench", sets: 3,
                repRange: "5", suggestedLoad: kg(100))
        ])

        #expect(exercise.intensity == nil)
        #expect(exercise.prescribedSets.allSatisfy { $0.intensity == nil })
    }

    // MARK: - Reported back beside what was logged

    @Test("The prescribed intensity appears in the snapshot beside what was logged")
    func snapshotCarriesIntensityBesideTheSets() throws {
        let context = try context()
        let plan = try PlanImporter.import(
            document([
                PlanDocumentExercise(
                    exerciseID: Self.bench, displayName: "Bench", sets: 2, repRange: "5",
                    suggestedLoad: kg(100),
                    intensity: IntensityTarget(scale: .rpe, value: "8"))
            ]),
            into: context, catalog: try catalog()
        )
        let exercise = try #require(
            plan.orderedWeeks.first?.orderedDays.first?.orderedExercises.first)
        for (index, reps) in [5, 4].enumerated() {
            let set = LoggedSet(setIndex: index, load: kg(100), reps: reps, isCompleted: true)
            context.insert(set)
            set.exercise = exercise
        }
        try context.save()

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)
        let reported = try #require(
            snapshot.plans.first?.weeks.first?.days.first?.exercises.first)

        #expect(reported.intensity == IntensityTarget(scale: .rpe, value: "8"))
        // What was asked for, beside what was put up against it. Nobody was
        // asked to rate the set, so nothing here reports a rating.
        #expect(reported.loggedSets.map(\.reps) == [5, 4])
        #expect(reported.prescribedSets.count == 2)
        #expect(reported.prescribedSets.allSatisfy {
            $0.intensity == IntensityTarget(scale: .rpe, value: "8")
        })
    }

    @Test("A ramp is reported back as the sets it is, not as one averaged prescription")
    func snapshotCarriesEverySet() throws {
        let context = try context()
        try PlanImporter.import(
            document([
                PlanDocumentExercise(
                    exerciseID: Self.squat, displayName: "Squat",
                    sets: [
                        SetPrescription(suggestedLoad: kg(60)),
                        SetPrescription(suggestedLoad: kg(70)),
                        SetPrescription(
                            suggestedLoad: kg(80),
                            intensity: IntensityTarget(scale: .rpe, value: "9"),
                            notes: "Top set"),
                    ],
                    repRange: "5")
            ]),
            into: context, catalog: try catalog()
        )

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)
        let reported = try #require(
            snapshot.plans.first?.weeks.first?.days.first?.exercises.first)

        #expect(reported.targetSets == 3)
        #expect(reported.prescribedSets.map { $0.suggestedLoad?.value } == [60, 70, 80])
        #expect(reported.prescribedSets.map(\.repRange) == ["5", "5", "5"])
        #expect(reported.prescribedSets.last?.intensity?.value == "9")
        #expect(reported.prescribedSets.last?.notes == "Top set")
    }

    @Test("A snapshot with a per-set prescription survives its own round trip")
    func snapshotRoundTrips() throws {
        let context = try context()
        try PlanImporter.import(
            document([
                PlanDocumentExercise(
                    exerciseID: Self.squat, displayName: "Squat",
                    sets: [
                        SetPrescription(repRange: "5", suggestedLoad: kg(60)),
                        SetPrescription(
                            repRange: "AMRAP", suggestedLoad: kg(80),
                            intensity: IntensityTarget(scale: .repsInReserve, value: "0")),
                    ])
            ]),
            into: context, catalog: try catalog()
        )
        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)
        let data = try TrainingSnapshot.makeEncoder().encode(snapshot)
        let decoded = try TrainingSnapshot.makeDecoder()
            .decode(TrainingSnapshot.self, from: data)
        let reported = try #require(
            decoded.plans.first?.weeks.first?.days.first?.exercises.first)

        #expect(reported.prescribedSets.map(\.repRange) == ["5", "AMRAP"])
        #expect(reported.prescribedSets.map { $0.suggestedLoad?.value } == [60, 80])
        #expect(reported.prescribedSets.last?.intensity
            == IntensityTarget(scale: .repsInReserve, value: "0"))
    }

    @Test("The exported JSON carries the per-set keys a reader actually reads")
    func snapshotWireShapeIsPinned() throws {
        let context = try context()
        try PlanImporter.import(
            document([
                PlanDocumentExercise(
                    exerciseID: Self.squat, displayName: "Squat",
                    sets: [
                        SetPrescription(repRange: "5", suggestedLoad: kg(60)),
                        SetPrescription(
                            repRange: "AMRAP", suggestedLoad: kg(80),
                            intensity: IntensityTarget(scale: .rpe, value: "9"),
                            notes: "Top set"),
                    ])
            ]),
            into: context, catalog: try catalog()
        )
        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)
        let data = try TrainingSnapshot.makeEncoder().encode(snapshot)

        // Read as untyped JSON rather than decoded back into the types that
        // wrote it: encoding and decoding with one pair of coding keys agrees
        // with itself whatever those keys are called, and what a reader on the
        // other side of the file depends on is the names.
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let plans = try #require(root["plans"] as? [[String: Any]])
        let weeks = try #require(plans.first?["weeks"] as? [[String: Any]])
        let days = try #require(weeks.first?["days"] as? [[String: Any]])
        let exercises = try #require(days.first?["exercises"] as? [[String: Any]])
        let sets = try #require(exercises.first?["prescribedSets"] as? [[String: Any]])

        #expect(sets.count == 2)
        #expect(sets.first?["repRange"] as? String == "5")
        #expect(sets.last?["notes"] as? String == "Top set")
        let intensity = try #require(sets.last?["intensity"] as? [String: Any])
        #expect(intensity["scale"] as? String == "rpe")
        #expect(intensity["value"] as? String == "9")
        let load = try #require(sets.last?["suggestedLoad"] as? [String: Any])
        #expect(load["value"] as? Double == 80)
        #expect(load["unit"] as? String == "kg")
    }

    @Test("A snapshot written before per-set prescriptions existed still reads")
    func olderSnapshotStillDecodes() throws {
        let json = """
        {
          "version": 1, "catalogVersion": 5,
          "generatedAt": "2023-11-14T22:13:20Z",
          "plans": [{
            "title": "Old block", "goal": "", "startDate": "2023-11-14T22:13:20Z",
            "catalogVersion": 5, "weekdays": [], "weeks": [{
              "ordinal": 1, "label": "", "isDeload": false, "days": [{
                "weekday": 2, "focus": "Push", "exercises": [{
                  "exerciseID": "barbell-bench-press", "displayName": "Bench",
                  "order": 0, "targetSets": 3, "repRange": "5", "loggedSets": []
                }]
              }]
            }]
          }]
        }
        """
        let decoded = try TrainingSnapshot.makeDecoder()
            .decode(TrainingSnapshot.self, from: Data(json.utf8))
        let exercise = try #require(
            decoded.plans.first?.weeks.first?.days.first?.exercises.first)

        #expect(exercise.targetSets == 3)
        #expect(exercise.intensity == nil)
        #expect(exercise.prescribedSets.isEmpty, "a format that could not say it did not say it")
    }

    // MARK: - What the lifter is shown

    @Test("Each logged row is seeded with its own set's load and reps")
    func seedingUsesEachSetsOwnPrescription() throws {
        let exercise = try imported([
            PlanDocumentExercise(
                exerciseID: Self.squat, displayName: "Squat",
                sets: [
                    SetPrescription(suggestedLoad: kg(60)),
                    SetPrescription(suggestedLoad: kg(70)),
                    SetPrescription(repRange: "3", suggestedLoad: kg(80)),
                ],
                repRange: "5")
        ])
        let seeds = exercise.prescribedSets.map {
            ($0.suggestedLoad?.value, RepPrescription.seededReps(for: $0.repRange))
        }

        #expect(seeds.map(\.0) == [60, 70, 80])
        #expect(seeds.map(\.1) == [5, 5, 3])
    }

    @Test("A set whose prescription names a range seeds no reps, as it always did")
    func aRangeStillSeedsNothing() {
        #expect(RepPrescription.seededReps(for: "8-12") == nil)
        #expect(RepPrescription.seededReps(for: nil) == nil)
        #expect(RepPrescription.targetText(for: nil) == "—")
        #expect(RepPrescription.targetText(for: "8-12") == "8-12")
    }

    @Test("An intensity target is shown as the plan wrote it, never converted")
    func intensityIsShownAsWritten() {
        #expect(IntensityPrescription.label(for: IntensityTarget(scale: .rpe, value: "8"))
            == "RPE 8")
        #expect(IntensityPrescription.label(for: IntensityTarget(scale: .repsInReserve, value: "2"))
            == "2 RIR")
        #expect(IntensityPrescription.label(
            for: IntensityTarget(scale: .percentOfOneRepMax, value: "80")) == "80% 1RM")
        // A scale nobody here has heard of is still shown, as written.
        #expect(IntensityPrescription.label(
            for: IntensityTarget(scale: IntensityScale(rawValue: "m/s"), value: "0.45"))
            == "m/s 0.45")
        #expect(IntensityPrescription.label(for: nil) == nil)
    }

    @Test("A prescription's summary states the sets it prescribes and nothing more")
    func summaryStatesWhatWasPrescribed() throws {
        let uniform = try imported([
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench", sets: 3, repRange: "8-12",
                intensity: IntensityTarget(scale: .rpe, value: "8"))
        ])
        #expect(PrescriptionSummary.text(for: uniform, unit: .kilograms) == "3 × 8-12 · RPE 8")

        // Sets that differ are spanned, never averaged and never represented by
        // one of them: five reps and three reps are three to five between them.
        let varying = try imported([
            PlanDocumentExercise(
                exerciseID: Self.squat, displayName: "Squat",
                sets: [
                    SetPrescription(repRange: "5"),
                    SetPrescription(repRange: "3"),
                ])
        ])
        #expect(PrescriptionSummary.text(for: varying, unit: .kilograms) == "2 × 3-5")

        let bare = try imported([
            PlanDocumentExercise(exerciseID: Self.bench, displayName: "Bench", sets: 4)
        ])
        #expect(PrescriptionSummary.text(for: bare, unit: .kilograms) == "4 sets")
    }

    @Test("A uniform prescription gains nothing under its rows")
    func uniformRowsSayNothingNew() throws {
        let plain = try imported([
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench", sets: 3, repRange: "8")
        ])
        #expect(plain.prescribedSets.allSatisfy {
            PrescriptionSummary.detail(for: $0, in: plain) == nil
        })

        // The effort every set asks for is stated once, above the table. A row
        // repeating it would be the screen saying the same thing three times.
        let rated = try imported([
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench", sets: 3, repRange: "8",
                intensity: IntensityTarget(scale: .rpe, value: "8"))
        ])
        #expect(PrescriptionSummary.text(for: rated, unit: .kilograms) == "3 × 8 · RPE 8")
        #expect(rated.prescribedSets.allSatisfy {
            PrescriptionSummary.detail(for: $0, in: rated) == nil
        })
    }

    /// The weight is the prescription when there is one, and the intensity is
    /// the reasoning behind it. A row that already shows 80 kg does not also
    /// need to be told the number was chosen to feel like an RPE 9.
    @Test("A set given a load is not also told the effort behind it")
    func loadedSetIsNotToldItsEffort() throws {
        let ramp = try imported([
            PlanDocumentExercise(
                exerciseID: Self.squat, displayName: "Squat",
                sets: [
                    SetPrescription(suggestedLoad: kg(60)),
                    SetPrescription(suggestedLoad: kg(70)),
                    SetPrescription(
                        suggestedLoad: kg(80),
                        intensity: IntensityTarget(scale: .rpe, value: "9"), notes: "Top set"),
                ],
                repRange: "5")
        ])

        #expect(ramp.prescribedSets.map { PrescriptionSummary.detail(for: $0, in: ramp) }
            == [nil, nil, "Top set"], "the note is its own; the RPE is what 80 kg already says")
    }

    /// Without a load the intensity *is* the prescription: "work up to a top
    /// single at RPE 8" is Claude deliberately leaving the weight to the lifter,
    /// and a row that hid it would leave him nothing to go on.
    @Test("A set given no load is told the effort asked of it, which is all it has")
    func unloadedSetStatesItsEffort() throws {
        let workUp = try imported([
            PlanDocumentExercise(
                exerciseID: Self.squat, displayName: "Squat",
                sets: [
                    SetPrescription(repRange: "5", suggestedLoad: kg(60)),
                    SetPrescription(repRange: "3", suggestedLoad: kg(80)),
                    SetPrescription(
                        repRange: "1", intensity: IntensityTarget(scale: .rpe, value: "8"),
                        notes: "Top single"),
                ])
        ])

        #expect(workUp.prescribedSets.map { PrescriptionSummary.detail(for: $0, in: workUp) }
            == [nil, nil, "RPE 8 · Top single"])
    }

    @Test("A set with neither a load nor an effort is told nothing extra")
    func unloadedSetWithNoEffortSaysNothing() throws {
        let bare = try imported([
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench", sets: 3, repRange: "8-12")
        ])

        #expect(bare.prescribedSets.allSatisfy {
            PrescriptionSummary.detail(for: $0, in: bare) == nil
        })
    }

    @Test("A note about one set of a drop set is stated on that set's row")
    func dropSetNoteSitsOnItsOwnRow() throws {
        let drop = try imported([
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench",
                sets: [
                    SetPrescription(),
                    SetPrescription(),
                    SetPrescription(repRange: "AMRAP", suggestedLoad: kg(70), notes: "Drop set"),
                ],
                repRange: "8", suggestedLoad: kg(100))
        ])

        #expect(drop.prescribedSets.map { PrescriptionSummary.detail(for: $0, in: drop) }
            == [nil, nil, "Drop set"])
    }

    @Test("A row the plan said nothing about adds no line of its own")
    func unprescribedRowAddsNothing() throws {
        let exercise = try imported([
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench", sets: 3, repRange: "8",
                intensity: IntensityTarget(scale: .rpe, value: "8"))
        ])

        // A warm-up, or a set added past the ones prescribed.
        #expect(PrescriptionSummary.detail(for: nil, in: exercise) == nil)
    }

    /// The session read before it is trained states the *shape* of a ramp in one
    /// line. Every set of it still reaches the lifter in full on the logging
    /// screen: its own load and reps as the placeholders in its two fields, and
    /// what Claude asked of it in particular on the row it is lifted on.
    @Test("A ramp is one line to browse and every set of it under the bar")
    func rampIsSpannedToBrowseAndStatedInFullToLog() throws {
        let ramp = try imported([
            PlanDocumentExercise(
                exerciseID: Self.squat, displayName: "Squat",
                sets: [
                    SetPrescription(suggestedLoad: kg(60)),
                    SetPrescription(
                        suggestedLoad: kg(80),
                        intensity: IntensityTarget(scale: .rpe, value: "9"), notes: "Top set"),
                ],
                repRange: "5")
        ])

        #expect(PrescriptionSummary.text(for: ramp, unit: .kilograms) == "2 × 5 · 60-80 kg")

        // Nothing about the individual sets is lost: the loads are what each
        // row's weight field is seeded with, and what was asked of the top set
        // is on the top set's row.
        let reading = SetRowPrescription(exercise: ramp, plans: [], unit: .kilograms)
        #expect(ramp.prescribedSets.map { reading.loadTarget($0) } == ["60", "80"])
        #expect(ramp.prescribedSets.map { PrescriptionSummary.detail(for: $0, in: ramp) }
            == [nil, "Top set"])
    }
}
