import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// A rest timer the lifter runs in the gym must not edit what Claude
/// prescribed.
///
/// The log view used to offer a menu of rest lengths whose buttons assigned
/// straight to `PlannedExercise.restSeconds` — the stored prescription, which
/// `SnapshotExporter` then exports. Tapping "60s" between sets silently rewrote
/// Claude's plan in the very record he reads back to judge whether the plan is
/// working. The rest line on an exercise is a control again, but what it writes
/// is `RestPreferences`, which never sees the model context; the prescription
/// stays read-only.
@MainActor
@Suite("Rest prescription")
struct RestPrescriptionTests {

    @Test("Running a rest timer leaves the prescribed rest exactly as prescribed")
    func timerDoesNotEditThePrescription() throws {
        let context = ModelContext(try StoreContainer.inMemory())
        let exercise = PlannedExercise(
            exerciseID: ExerciseID(rawValue: "barbell-back-squat"),
            displayName: "Barbell Back Squat",
            order: 0, targetSets: 5, repRange: "5", restSeconds: 180
        )
        context.insert(exercise)
        try context.saveOrThrow()

        // The lifter runs a rest of his own, nothing like the prescription.
        let timer = RestTimerModel()
        timer.start(seconds: 45, context: "Rest")
        timer.addTime(30)
        timer.stop()

        try context.saveOrThrow()
        let loaded = try #require(try context.fetch(FetchDescriptor<PlannedExercise>()).first)
        #expect(loaded.restSeconds == 180)
    }

    @Test("An exercise with no prescribed rest still has none after a session-local timer")
    func unprescribedRestStaysUnprescribed() throws {
        // The old label read "Set a rest timer", which solicited a number and
        // then stored it as though Claude had written it. Absence has to
        // survive a workout.
        let context = ModelContext(try StoreContainer.inMemory())
        let exercise = PlannedExercise(
            exerciseID: ExerciseID(rawValue: "push-up"), displayName: "Push Up",
            order: 0, targetSets: 3, repRange: "10"
        )
        context.insert(exercise)
        try context.saveOrThrow()

        let timer = RestTimerModel()
        timer.start(seconds: 90, context: "Rest")
        timer.stop()

        try context.saveOrThrow()
        let loaded = try #require(try context.fetch(FetchDescriptor<PlannedExercise>()).first)
        #expect(loaded.restSeconds == nil)
    }

    @Test("Editing the lifter's clock leaves the prescribed rest exactly as prescribed")
    func editingTheClockDoesNotEditThePrescription() throws {
        let context = ModelContext(try StoreContainer.inMemory())
        let id = ExerciseID(rawValue: "barbell-bench-press")
        let exercise = PlannedExercise(
            exerciseID: id, displayName: "Barbell Bench Press",
            order: 0, targetSets: 5, repRange: "5", restSeconds: 180
        )
        context.insert(exercise)
        try context.saveOrThrow()

        // Everything the sheet can do to an exercise's clock, in one go.
        let preferences = RestPreferences(store: UserDefaultsRestStore(defaults: isolatedDefaults()))
        preferences.setRest(.seconds(45), for: id)
        preferences.setRest(.off, for: id)
        preferences.setTimersEnabled(false)

        try context.saveOrThrow()
        let loaded = try #require(try context.fetch(FetchDescriptor<PlannedExercise>()).first)
        #expect(loaded.restSeconds == 180)
        // And what the snapshot would carry is still Claude's number.
        #expect(loaded.prescribedSets.count == 5)
    }

    /// A defaults suite of this test's own, so nothing it writes reaches the
    /// simulator's real preferences or the next test.
    private func isolatedDefaults() -> UserDefaults {
        let name = "rest-prescription-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { return .standard }
        return defaults
    }

    @Test("No prescribed rest draws no label — the app neither invents one nor asks for one")
    func absentRestDrawsNothing() {
        #expect(RestPrescription.label(seconds: nil) == nil)
    }

    @Test("A prescribed rest is written out as the plan set it")
    func prescribedRestLabel() {
        #expect(RestPrescription.label(seconds: 90) == "Rest 1min 30s")
        #expect(RestPrescription.label(seconds: 45) == "Rest 45s")
        #expect(RestPrescription.durationText(120) == "2min")
        #expect(RestPrescription.durationText(59) == "59s")
        #expect(RestPrescription.durationText(0) == "0s")
    }
}
