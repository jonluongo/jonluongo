import Testing
@testable import LiftingPlan

@Suite("ProgressionEngine")
struct ProgressionEngineTests {

    @Test("Pushes load when all reps hit at manageable effort")
    func pushesWhenEarned() {
        let history = ExerciseHistory(
            exerciseID: ExerciseID(rawValue: "bench-press"),
            displayName: "Bench Press",
            repTargetUpper: 10,
            recentSets: [
                SetRecord(load: Mass(value: 100, unit: .pounds), reps: 10, rpe: 7),
                SetRecord(load: Mass(value: 100, unit: .pounds), reps: 10, rpe: 8),
                SetRecord(load: Mass(value: 100, unit: .pounds), reps: 10, rpe: 8),
            ]
        )
        let suggestion = ProgressionEngine.suggestion(for: history)
        #expect(suggestion.isPush)
        // 100 is >= 50, so +5 lb.
        #expect(suggestion.suggestedLoad?.value == 105)
        #expect(suggestion.suggestedLoad?.unit == .pounds)
    }

    @Test("Uses small increments on lighter lifts")
    func smallIncrementOnLightWeight() {
        let history = ExerciseHistory(
            exerciseID: ExerciseID(rawValue: "lateral-raise"),
            displayName: "Lateral Raise",
            repTargetUpper: 12,
            recentSets: [
                SetRecord(load: Mass(value: 20, unit: .pounds), reps: 12, rpe: 7),
                SetRecord(load: Mass(value: 20, unit: .pounds), reps: 12, rpe: 7),
            ]
        )
        let suggestion = ProgressionEngine.suggestion(for: history)
        #expect(suggestion.isPush)
        #expect(suggestion.suggestedLoad?.value == 22.5)
        #expect(suggestion.suggestedLoad?.unit == .pounds)
    }

    @Test("Holds load when reps were met but effort was maximal")
    func holdsWhenGrindy() {
        let history = ExerciseHistory(
            exerciseID: ExerciseID(rawValue: "squat"),
            displayName: "Squat",
            repTargetUpper: 8,
            recentSets: [
                SetRecord(load: Mass(value: 185, unit: .pounds), reps: 8, rpe: 9),
                SetRecord(load: Mass(value: 185, unit: .pounds), reps: 8, rpe: 10),
            ]
        )
        let suggestion = ProgressionEngine.suggestion(for: history)
        #expect(!suggestion.isPush)
        #expect(suggestion.suggestedLoad?.value == 185)
        #expect(suggestion.suggestedLoad?.unit == .pounds)
    }

    @Test("Holds when reps slipped below target")
    func holdsWhenRepsMissed() {
        let history = ExerciseHistory(
            exerciseID: ExerciseID(rawValue: "row"),
            displayName: "Row",
            repTargetUpper: 10,
            recentSets: [
                SetRecord(load: Mass(value: 135, unit: .pounds), reps: 10, rpe: 8),
                SetRecord(load: Mass(value: 135, unit: .pounds), reps: 7, rpe: 9),
            ]
        )
        let suggestion = ProgressionEngine.suggestion(for: history)
        #expect(!suggestion.isPush)
        #expect(suggestion.suggestedLoad?.value == 135)
        #expect(suggestion.suggestedLoad?.unit == .pounds)
    }

    @Test("No history yields no weight but guidance")
    func noHistory() {
        let history = ExerciseHistory(
            exerciseID: ExerciseID(rawValue: "deadlift"), displayName: "Deadlift",
            repTargetUpper: 5, recentSets: []
        )
        let suggestion = ProgressionEngine.suggestion(for: history)
        #expect(suggestion.suggestedLoad == nil)
        #expect(!suggestion.isPush)
    }

    @Test("Bodyweight movement pushes via reps, not load")
    func bodyweightPush() {
        let history = ExerciseHistory(
            exerciseID: ExerciseID(rawValue: "pull-up"),
            displayName: "Pull-Up",
            repTargetUpper: 8,
            recentSets: [
                SetRecord(load: nil, reps: 8, rpe: 7),
                SetRecord(load: nil, reps: 8, rpe: 8),
            ]
        )
        let suggestion = ProgressionEngine.suggestion(for: history)
        #expect(suggestion.suggestedLoad == nil)
        #expect(suggestion.isPush)
    }

    @Test("Missing RPE is treated as room to grow")
    func missingRPEProgresses() {
        let history = ExerciseHistory(
            exerciseID: ExerciseID(rawValue: "overhead-press"),
            displayName: "Overhead Press",
            repTargetUpper: 6,
            recentSets: [SetRecord(load: Mass(value: 95, unit: .pounds), reps: 6, rpe: nil)]
        )
        let suggestion = ProgressionEngine.suggestion(for: history)
        #expect(suggestion.isPush)
        #expect(suggestion.suggestedLoad?.value == 100)
        #expect(suggestion.suggestedLoad?.unit == .pounds)
    }

    @Test("Finds the true heaviest set across sets logged in different units")
    func comparesAcrossMixedUnits() {
        // 90 kg (~198.4 lb) is heavier than 185 lb (~83.9 kg): the kilogram
        // comparison must pick the 90 kg set as the top set, not the 185 lb one.
        let history = ExerciseHistory(
            exerciseID: ExerciseID(rawValue: "squat"),
            displayName: "Squat",
            repTargetUpper: 5,
            recentSets: [
                SetRecord(load: Mass(value: 185, unit: .pounds), reps: 5, rpe: 7),
                SetRecord(load: Mass(value: 90, unit: .kilograms), reps: 5, rpe: 7),
            ]
        )
        let suggestion = ProgressionEngine.suggestion(for: history)
        #expect(suggestion.isPush)
        #expect(suggestion.suggestedLoad?.unit == .kilograms)
        // 90 kg is >= 50, so +5 kg -> 95, already a multiple of 2.5.
        #expect(suggestion.suggestedLoad?.value == 95)
    }

    @Test("Rounds to the nearest 2.5")
    func rounding() {
        #expect(ProgressionEngine.roundToNearest(104, step: 2.5) == 105)
        #expect(ProgressionEngine.roundToNearest(103.7, step: 2.5) == 102.5)
        #expect(ProgressionEngine.roundToNearest(101.2, step: 2.5) == 100)
        #expect(ProgressionEngine.incrementFor(weight: 45) == 2.5)
        #expect(ProgressionEngine.incrementFor(weight: 50) == 5)
    }

    @Test("Performance summary lists logged exercises with a direction")
    func performanceSummary() {
        let histories = [
            ExerciseHistory(
                exerciseID: ExerciseID(rawValue: "bench-press"), displayName: "Bench Press",
                repTargetUpper: 10,
                recentSets: [SetRecord(load: Mass(value: 100, unit: .pounds), reps: 10, rpe: 7)]
            ),
            ExerciseHistory(
                exerciseID: ExerciseID(rawValue: "untouched"), displayName: "Untouched",
                repTargetUpper: 10, recentSets: []
            ),
        ]
        let summary = ProgressionEngine.performanceSummary(from: histories)
        #expect(summary.contains("Bench Press"))
        #expect(summary.contains("push"))
        #expect(summary.contains("lb"))
        // Exercises with no logged sets are skipped.
        #expect(!summary.contains("Untouched"))
    }
}
