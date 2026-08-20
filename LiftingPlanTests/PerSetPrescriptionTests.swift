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
            snapshot.firstPrescribedExercise)

        #expect(reported.intensity == IntensityTarget(scale: .rpe, value: "8"))
        // What was asked for, beside what was put up against it. Nobody was
        // asked to rate the set, so nothing here reports a rating.
        #expect(snapshot.log.sorted { $0.setIndex < $1.setIndex }.map(\.reps) == [5, 4])
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
            snapshot.firstPrescribedExercise)

        #expect(reported.sets == 3)
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
            decoded.firstPrescribedExercise)

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
        let routines = try #require(root["routines"] as? [[String: Any]])
        let document = try #require(routines.first?["document"] as? [String: Any])
        let weeks = try #require(document["blocks"] as? [[String: Any]])
        let days = try #require(weeks.first?["days"] as? [[String: Any]])
        let exercises = try #require(days.first?["exercises"] as? [[String: Any]])
        // The sets the plan listed one at a time, under the key the format that
        // wrote them uses — the block travels as the document the coach wrote,
        // so this is his own key rather than a restatement of it.
        let sets = try #require(exercises.first?["sets"] as? [[String: Any]])

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

    @Test("A snapshot written before this format existed is refused, not read half-way")
    func olderSnapshotIsRefused() throws {
        // The shape moved in version 3: a block used to be restated beside the
        // document rather than carried as it. An older file decoded leniently
        // would report a lifter with no training at all, so it is refused and
        // says which build wrote it.
        let json = """
        {
          "version": 1, "catalogVersion": 5,
          "generatedAt": "2023-11-14T22:13:20Z",
          "plans": [{
            "title": "Old block", "goal": "", "startDate": "2023-11-14T22:13:20Z",
            "catalogVersion": 5, "weekdays": [], "weeks": []
          }]
        }
        """

        #expect(throws: DocumentRefusal.snapshotVersionMismatch(
            1, understood: TrainingSnapshot.currentVersion)
        ) {
            try TrainingSnapshot.makeDecoder()
                .decode(TrainingSnapshot.self, from: Data(json.utf8))
        }
    }
}
