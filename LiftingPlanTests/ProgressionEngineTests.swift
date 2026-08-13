import Testing
@testable import LiftingPlan

@Suite("ProgressionEngine")
struct ProgressionEngineTests {

    @Test("Pushes load when all reps hit at manageable effort")
    func pushesWhenEarned() {
        let history = ExerciseHistory(
            name: "Bench Press",
            repTargetUpper: 10,
            recentSets: [
                SetRecord(weight: 100, reps: 10, rpe: 7),
                SetRecord(weight: 100, reps: 10, rpe: 8),
                SetRecord(weight: 100, reps: 10, rpe: 8),
            ]
        )
        let suggestion = ProgressionEngine.suggestion(for: history)
        #expect(suggestion.isPush)
        // 100 is >= 50, so +5 lb.
        #expect(suggestion.suggestedWeight == 105)
    }

    @Test("Uses small increments on lighter lifts")
    func smallIncrementOnLightWeight() {
        let history = ExerciseHistory(
            name: "Lateral Raise",
            repTargetUpper: 12,
            recentSets: [
                SetRecord(weight: 20, reps: 12, rpe: 7),
                SetRecord(weight: 20, reps: 12, rpe: 7),
            ]
        )
        let suggestion = ProgressionEngine.suggestion(for: history)
        #expect(suggestion.isPush)
        #expect(suggestion.suggestedWeight == 22.5)
    }

    @Test("Holds load when reps were met but effort was maximal")
    func holdsWhenGrindy() {
        let history = ExerciseHistory(
            name: "Squat",
            repTargetUpper: 8,
            recentSets: [
                SetRecord(weight: 185, reps: 8, rpe: 9),
                SetRecord(weight: 185, reps: 8, rpe: 10),
            ]
        )
        let suggestion = ProgressionEngine.suggestion(for: history)
        #expect(!suggestion.isPush)
        #expect(suggestion.suggestedWeight == 185)
    }

    @Test("Holds when reps slipped below target")
    func holdsWhenRepsMissed() {
        let history = ExerciseHistory(
            name: "Row",
            repTargetUpper: 10,
            recentSets: [
                SetRecord(weight: 135, reps: 10, rpe: 8),
                SetRecord(weight: 135, reps: 7, rpe: 9),
            ]
        )
        let suggestion = ProgressionEngine.suggestion(for: history)
        #expect(!suggestion.isPush)
        #expect(suggestion.suggestedWeight == 135)
    }

    @Test("No history yields no weight but guidance")
    func noHistory() {
        let history = ExerciseHistory(name: "Deadlift", repTargetUpper: 5, recentSets: [])
        let suggestion = ProgressionEngine.suggestion(for: history)
        #expect(suggestion.suggestedWeight == nil)
        #expect(!suggestion.isPush)
    }

    @Test("Bodyweight movement pushes via reps, not load")
    func bodyweightPush() {
        let history = ExerciseHistory(
            name: "Pull-Up",
            repTargetUpper: 8,
            recentSets: [
                SetRecord(weight: nil, reps: 8, rpe: 7),
                SetRecord(weight: nil, reps: 8, rpe: 8),
            ]
        )
        let suggestion = ProgressionEngine.suggestion(for: history)
        #expect(suggestion.suggestedWeight == nil)
        #expect(suggestion.isPush)
    }

    @Test("Missing RPE is treated as room to grow")
    func missingRPEProgresses() {
        let history = ExerciseHistory(
            name: "Overhead Press",
            repTargetUpper: 6,
            recentSets: [SetRecord(weight: 95, reps: 6, rpe: nil)]
        )
        let suggestion = ProgressionEngine.suggestion(for: history)
        #expect(suggestion.isPush)
        #expect(suggestion.suggestedWeight == 100)
    }

    @Test("Rounds to the nearest 2.5")
    func rounding() {
        #expect(ProgressionEngine.roundToNearest(103.7, step: 2.5) == 105)
        #expect(ProgressionEngine.roundToNearest(101.2, step: 2.5) == 100)
        #expect(ProgressionEngine.incrementFor(weight: 45) == 2.5)
        #expect(ProgressionEngine.incrementFor(weight: 50) == 5)
    }

    @Test("Performance summary lists logged exercises with a direction")
    func performanceSummary() {
        let histories = [
            ExerciseHistory(name: "Bench Press", repTargetUpper: 10,
                            recentSets: [SetRecord(weight: 100, reps: 10, rpe: 7)]),
            ExerciseHistory(name: "Untouched", repTargetUpper: 10, recentSets: []),
        ]
        let summary = ProgressionEngine.performanceSummary(from: histories)
        #expect(summary.contains("Bench Press"))
        #expect(summary.contains("push"))
        // Exercises with no logged sets are skipped.
        #expect(!summary.contains("Untouched"))
    }
}
