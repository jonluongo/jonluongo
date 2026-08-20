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
        preferences.setClockIsOn(false)

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

    /// One spelling, and it is the one the wheels beside the sentence use. It
    /// wrote `3min`, which reads as a typo in the sentence that is its only
    /// caller, on a screen whose pickers already said `3 min`.
    @Test("A prescribed rest is written the way the wheels beside it are")
    func prescribedRestReadsAsASentence() {
        #expect(RestPrescription.durationText(180) == "3 min")
        #expect(RestPrescription.durationText(150) == "2 min 30 s")
        #expect(RestPrescription.durationText(120) == "2 min")
        #expect(RestPrescription.durationText(59) == "59 s")
        #expect(RestPrescription.durationText(0) == "0 s")
    }
}
