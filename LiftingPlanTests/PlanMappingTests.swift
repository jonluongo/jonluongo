import Testing
@testable import LiftingPlan

@Suite("Plan blueprint mapping")
struct PlanMappingTests {

    @Test("Maps a blueprint into an ordered SwiftData plan")
    func mapsOrdered() {
        let blueprint = PlanBlueprint(days: [
            DayBlueprint(weekday: .monday, focus: "Push", durationMinutes: 45, exercises: [
                ExerciseBlueprint(name: "Bench", muscleGroup: "Chest", repRange: "6-10", sets: 4, restSeconds: 90, suggestedWeight: nil, tempo: "3-0-1-0", notes: nil),
                ExerciseBlueprint(name: "OHP", muscleGroup: "Shoulders", repRange: "8-12", sets: 3, restSeconds: 75, suggestedWeight: nil, tempo: nil, notes: nil),
            ]),
            DayBlueprint(weekday: .wednesday, focus: "Pull", durationMinutes: 45, exercises: []),
        ])

        let plan = blueprint.makeWorkoutPlan(goal: "Get strong", durationMinutes: 45, wasModelGenerated: true)

        #expect(plan.sessions.count == 2)
        #expect(plan.wasModelGenerated)
        let ordered = plan.orderedSessions
        #expect(ordered[0].weekday == .monday)
        #expect(ordered[0].order == 0)
        #expect(ordered[1].order == 1)
        #expect(ordered[0].orderedExercises.map(\.name) == ["Bench", "OHP"])
        #expect(ordered[0].orderedExercises[0].order == 0)
        #expect(ordered[0].orderedExercises[1].order == 1)
    }

    @Test("Clamps out-of-range values and fills empty fields")
    func clampsValues() {
        let blueprint = PlanBlueprint(days: [
            DayBlueprint(weekday: .friday, focus: "", durationMinutes: 2, exercises: [
                ExerciseBlueprint(name: "Weird", muscleGroup: "", repRange: "", sets: 99, restSeconds: 5, suggestedWeight: nil, tempo: nil, notes: nil),
            ]),
        ])

        let plan = blueprint.makeWorkoutPlan(goal: "", durationMinutes: 30, wasModelGenerated: false)
        let session = plan.orderedSessions[0]
        let exercise = session.orderedExercises[0]

        #expect(session.focus == "Training")           // empty focus defaulted
        #expect(session.targetDurationMinutes == 10)    // clamped up from 2
        #expect(exercise.targetSets == 8)               // clamped down from 99
        #expect(exercise.restSeconds == 15)             // clamped up from 5
        #expect(exercise.repRange == "8-12")            // empty rep range defaulted
    }

    @Test("Parses rep-range bounds")
    func repRangeBounds() {
        let ranged = PlannedExercise(name: "A", order: 0, targetSets: 3, repRange: "8-12", restSeconds: 60)
        #expect(ranged.repTargetLowerBound == 8)
        #expect(ranged.repTargetUpperBound == 12)

        let single = PlannedExercise(name: "B", order: 0, targetSets: 3, repRange: "5", restSeconds: 60)
        #expect(single.repTargetLowerBound == 5)
        #expect(single.repTargetUpperBound == 5)
    }

    @Test("Estimated 1RM uses the Epley formula")
    func epley() {
        let set = SetLog(setIndex: 0, weight: 100, reps: 10)
        // 100 * (1 + 10/30) = 133.33…
        let est = try #require(set.estimatedOneRepMax)
        #expect(abs(est - 133.333) < 0.01)

        let bodyweight = SetLog(setIndex: 0, weight: nil, reps: 12)
        #expect(bodyweight.estimatedOneRepMax == nil)
    }
}
