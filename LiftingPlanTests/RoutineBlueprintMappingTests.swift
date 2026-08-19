import Testing
@testable import LiftingPlan
import LiftingKit

@Suite("Routine blueprint mapping")
struct RoutineBlueprintMappingTests {

    @Test("Maps a blueprint into an ordered SwiftData plan")
    func mapsOrdered() {
        let blueprint = RoutineBlueprint(goal: "Get strong", durationMinutes: 45, days: [
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

        let plan = blueprint.makeWorkoutPlan(catalogVersion: 7)

        #expect(plan.catalogVersion == 7)   // carried through, not defaulted
        #expect(plan.goal == "Get strong")
        #expect(plan.durationMinutes == 45)
        // The training days are a restatement of the days prescribed.
        #expect(plan.orderedWeekdays == [.monday, .wednesday])
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

    @Test("Records unusual values exactly as prescribed, altering nothing")
    func recordsValuesAsGiven() {
        // Every value here would previously have been clamped or substituted.
        // Each is legitimate: 10x3 is a real prescription, 720 seconds is a
        // real rest between heavy singles, and an unstated rep range means
        // unstated — not "8-12".
        let blueprint = RoutineBlueprint(durationMinutes: 30, days: [
            DayBlueprint(weekday: .friday, focus: "", durationMinutes: 5, exercises: [
                ExerciseBlueprint(
                    exerciseID: ExerciseID(rawValue: "barbell-back-squat"), displayName: "Squat",
                    repRange: "", sets: 10, restSeconds: 720,
                    suggestedLoad: nil, tempo: nil, notes: nil
                ),
            ]),
        ])

        let plan = blueprint.makeWorkoutPlan(catalogVersion: 7)
        let day = plan.orderedWeeks[0].orderedDays[0]
        let exercise = day.orderedExercises[0]

        #expect(day.focus == "")                 // no label invented
        #expect(day.durationMinutes == 5)        // not floored to 10
        #expect(exercise.targetSets == 10)       // not capped at 8
        #expect(exercise.restSeconds == 720)     // not capped at 600
        #expect(exercise.repRange == "")         // no rep range invented
        #expect(RepRange(exercise.repRange).isEmpty)  // and it reads as "unstated"
    }

    @Test("Zero prescribed sets is recorded as zero, not floored to one")
    func recordsZeroSets() {
        let blueprint = RoutineBlueprint(days: [
            DayBlueprint(weekday: .monday, focus: "Push", durationMinutes: 45, exercises: [
                ExerciseBlueprint(
                    exerciseID: ExerciseID(rawValue: "barbell-bench-press"), displayName: "Bench",
                    repRange: "5", sets: 0, restSeconds: 0,
                    suggestedLoad: nil, tempo: nil, notes: nil
                ),
            ]),
        ])

        let plan = blueprint.makeWorkoutPlan(catalogVersion: 7)
        let exercise = plan.orderedWeeks[0].orderedDays[0].orderedExercises[0]

        #expect(exercise.targetSets == 0)
        #expect(exercise.restSeconds == 0)
    }

    @Test("Carries a suggested load through with its unit intact")
    func suggestedLoadCarriesUnit() {
        let blueprint = RoutineBlueprint(days: [
            DayBlueprint(weekday: .monday, focus: "Push", durationMinutes: 45, exercises: [
                ExerciseBlueprint(
                    exerciseID: ExerciseID(rawValue: "barbell-bench-press"), displayName: "Bench",
                    repRange: "6-10", sets: 4, restSeconds: 90,
                    suggestedLoad: Mass(value: 60, unit: .kilograms), tempo: nil, notes: nil
                ),
            ]),
        ])

        let plan = blueprint.makeWorkoutPlan(catalogVersion: 7)
        let exercise = plan.orderedWeeks[0].orderedDays[0].orderedExercises[0]

        #expect(exercise.suggestedLoad?.value == 60)
        #expect(exercise.suggestedLoad?.unit == .kilograms)
    }

    @Test("A hold prescribed in seconds is not turned into a rep target")
    func timedPrescriptionIsNotARepTarget() {
        // It used to seed 30 reps — a number nobody prescribed and nobody
        // performed, counted as reps by everything downstream.
        #expect(RepPrescription.seededReps(for: "30 seconds") == nil)
        // The prescription itself is untouched: it is shown as it was written.
        #expect(RepPrescription.targetText(for: "30 seconds") == "30 seconds")
    }
}
