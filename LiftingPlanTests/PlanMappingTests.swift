import Testing
@testable import LiftingPlan

@Suite("Plan blueprint mapping")
struct PlanMappingTests {

    @Test("Maps a blueprint into an ordered SwiftData plan")
    func mapsOrdered() {
        let blueprint = PlanBlueprint(days: [
            DayBlueprint(weekday: .monday, focus: "Push", durationMinutes: 45, exercises: [
                ExerciseBlueprint(
                    exerciseID: ExerciseID(rawValue: "barbell-bench-press"), displayName: "Bench",
                    repRange: "6-10", sets: 4, restSeconds: 90,
                    suggestedLoad: nil, tempo: "3-0-1-0", notes: nil
                ),
                ExerciseBlueprint(
                    exerciseID: ExerciseID(rawValue: "overhead-press"), displayName: "OHP",
                    repRange: "8-12", sets: 3, restSeconds: 75,
                    suggestedLoad: nil, tempo: nil, notes: nil
                ),
            ]),
            DayBlueprint(weekday: .wednesday, focus: "Pull", durationMinutes: 45, exercises: []),
        ])

        let plan = blueprint.makeWorkoutPlan(goal: "Get strong", durationMinutes: 45, wasModelGenerated: true)

        #expect(plan.wasModelGenerated)
        #expect(plan.orderedWeeks.count == 1)
        let week = plan.orderedWeeks[0]
        let ordered = week.orderedDays
        #expect(ordered.count == 2)
        #expect(ordered[0].weekday == .monday)
        #expect(ordered[1].weekday == .wednesday)
        #expect(ordered[0].orderedExercises.map(\.exerciseID) == [
            ExerciseID(rawValue: "barbell-bench-press"), ExerciseID(rawValue: "overhead-press"),
        ])
        #expect(ordered[0].orderedExercises.map(\.displayName) == ["Bench", "OHP"])
        #expect(ordered[0].orderedExercises[0].order == 0)
        #expect(ordered[0].orderedExercises[1].order == 1)
        #expect(ordered[1].orderedExercises.isEmpty)
    }

    @Test("Clamps out-of-range values and fills empty fields")
    func clampsValues() {
        let blueprint = PlanBlueprint(days: [
            DayBlueprint(weekday: .friday, focus: "", durationMinutes: 2, exercises: [
                ExerciseBlueprint(
                    exerciseID: ExerciseID(rawValue: "weird-exercise"), displayName: "Weird",
                    repRange: "", sets: 99, restSeconds: 5,
                    suggestedLoad: nil, tempo: nil, notes: nil
                ),
            ]),
        ])

        let plan = blueprint.makeWorkoutPlan(goal: "", durationMinutes: 30, wasModelGenerated: false)
        let day = plan.orderedWeeks[0].orderedDays[0]
        let exercise = day.orderedExercises[0]

        #expect(day.focus == "Training")                // empty focus defaulted
        #expect(day.durationMinutes == 10)               // clamped up from 2
        #expect(exercise.targetSets == 8)                // clamped down from 99
        #expect(exercise.restSeconds == 15)              // clamped up from 5
        #expect(exercise.repRange == "8-12")             // empty rep range defaulted
    }

    @Test("Carries a suggested load through with its unit intact")
    func suggestedLoadCarriesUnit() {
        let blueprint = PlanBlueprint(days: [
            DayBlueprint(weekday: .monday, focus: "Push", durationMinutes: 45, exercises: [
                ExerciseBlueprint(
                    exerciseID: ExerciseID(rawValue: "barbell-bench-press"), displayName: "Bench",
                    repRange: "6-10", sets: 4, restSeconds: 90,
                    suggestedLoad: Mass(value: 60, unit: .kilograms), tempo: nil, notes: nil
                ),
            ]),
        ])

        let plan = blueprint.makeWorkoutPlan(goal: "Get strong", durationMinutes: 45, wasModelGenerated: true)
        let exercise = plan.orderedWeeks[0].orderedDays[0].orderedExercises[0]

        #expect(exercise.suggestedLoad?.value == 60)
        #expect(exercise.suggestedLoad?.unit == .kilograms)
    }

    @Test("Parses rep-range bounds when building exercise history")
    func repRangeBounds() {
        let ranged = PlannedExercise(
            exerciseID: ExerciseID(rawValue: "a"), displayName: "A",
            order: 0, targetSets: 3, repRange: "8-12", restSeconds: 60
        )
        #expect(PerformanceHistory.history(from: ranged).repTargetUpper == 12)

        let single = PlannedExercise(
            exerciseID: ExerciseID(rawValue: "b"), displayName: "B",
            order: 0, targetSets: 3, repRange: "5", restSeconds: 60
        )
        #expect(PerformanceHistory.history(from: single).repTargetUpper == 5)
    }

    @Test("Estimated 1RM uses the Epley formula, in kilograms")
    func epley() throws {
        let set = LoggedSet(setIndex: 0, load: Mass(value: 100, unit: .kilograms), reps: 10)
        // 100 * (1 + 10/30) = 133.33…
        let est = try #require(set.estimatedOneRepMaxKilograms)
        #expect(abs(est - 133.333) < 0.01)

        let bodyweight = LoggedSet(setIndex: 0, load: nil, reps: 12)
        #expect(bodyweight.estimatedOneRepMaxKilograms == nil)
    }
}
