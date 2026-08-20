import Testing
import Foundation
@testable import LiftingPlan
import LiftingKit

@Suite("Exercise trend")
struct ExerciseTrendTests {

    private let squat = ExerciseID(rawValue: "back-squat")

    private func completedSet(
        _ value: Double, _ unit: MassUnit, reps: Int, at date: Date, setIndex: Int = 0
    ) -> LoggedSet {
        LoggedSet(
            setIndex: setIndex, load: Mass(value: value, unit: unit), reps: reps,
            isCompleted: true, isWarmup: false, completedAt: date
        )
    }

    /// A hold, logged in seconds with no load and no reps.
    private func heldSet(_ seconds: Int, at date: Date, setIndex: Int = 0) -> LoggedSet {
        LoggedSet(
            setIndex: setIndex, load: nil, reps: 0, durationSeconds: seconds,
            isCompleted: true, isWarmup: false, completedAt: date)
    }

    /// A carry, logged over a distance in the unit it was prescribed in.
    private func carriedSet(
        _ metres: Double, at date: Date, setIndex: Int = 0
    ) -> LoggedSet {
        LoggedSet(
            setIndex: setIndex, load: nil, reps: 0,
            distance: Distance(value: metres, unit: .metres),
            isCompleted: true, isWarmup: false, completedAt: date)
    }

    private func exercise(
        id: ExerciseID, order: Int = 0, sets: [LoggedSet]
    ) -> PlannedExercise {
        let planned = PlannedExercise(
            exerciseID: id, displayName: "Back Squat", order: order,
            targetSets: sets.count, repRange: "5", restSeconds: 180
        )
        planned.loggedSets = sets
        return planned
    }

    private func plan(exercises: [PlannedExercise]) -> TrainingPlan {
        let day = WorkoutDay(weekday: .monday, focus: "Legs")
        day.exercises = exercises
        let week = TrainingWeek(ordinal: 1)
        week.days = [day]
        let trainingPlan = TrainingPlan(title: "Block")
        trainingPlan.weeks = [week]
        return trainingPlan
    }

    @Test("Selects the heaviest set as the top set, breaking ties by reps")
    func bestSetSelection() throws {
        let now = Date()
        let planned = exercise(id: squat, sets: [
            completedSet(80, .kilograms, reps: 10, at: now, setIndex: 0),
            completedSet(100, .kilograms, reps: 5, at: now, setIndex: 1),
            // Same weight as the set above; the tie should fall to more reps.
            completedSet(100, .kilograms, reps: 8, at: now, setIndex: 2),
        ])

        let trends = ExerciseTrend.build(from: [plan(exercises: [planned])])
        let trend = try #require(trends.first { $0.exerciseID == squat })
        #expect(trend.points.count == 1)
        let point = try #require(trend.points.first)
        #expect(point.topLoad == Mass(value: 100, unit: .kilograms))
        #expect(point.topReps == 8)
    }

    @Test("Best-set selection compares across units correctly — a naive raw-value comparison would pick the wrong set")
    func bestSetSelectionAcrossMixedUnits() throws {
        let now = Date()
        // 90 kg ≈ 198.4 lb is the heavier set, but its raw `.value` (90) is
        // smaller than the 150 lb set's raw `.value` (150). A comparison that
        // ignored unit and compared `.value` directly — which `Mass`'s exact,
        // representation-preserving `==` invites if you reach for the wrong
        // operator — would wrongly pick the 150 lb set as the top set.
        let heavierInKilograms = completedSet(90, .kilograms, reps: 5, at: now, setIndex: 0)
        let lighterInPounds = completedSet(150, .pounds, reps: 5, at: now, setIndex: 1)
        #expect(heavierInKilograms.load!.kilograms > lighterInPounds.load!.kilograms)
        #expect(heavierInKilograms.load!.value < lighterInPounds.load!.value)

        let planned = exercise(id: squat, sets: [heavierInKilograms, lighterInPounds])
        let trends = ExerciseTrend.build(from: [plan(exercises: [planned])])
        let trend = try #require(trends.first { $0.exerciseID == squat })
        let point = try #require(trend.points.first)

        #expect(point.topLoad == Mass(value: 90, unit: .kilograms))
        #expect(point.topLoad?.kilograms != Mass(value: 150, unit: .pounds).kilograms)
    }

    @Test("Sessions are ordered oldest to newest and report what was lifted, not a verdict on it")
    func sessionsAreOrderedAndUnjudged() throws {
        let earlier = Date(timeIntervalSince1970: 0)
        let later = Date(timeIntervalSince1970: 7 * 24 * 60 * 60)

        let session1 = exercise(
            id: squat, order: 0,
            sets: [completedSet(60, .kilograms, reps: 5, at: earlier)]
        )
        let session2 = exercise(
            id: squat, order: 1,
            sets: [completedSet(80, .kilograms, reps: 5, at: later)]
        )

        let trends = ExerciseTrend.build(from: [plan(exercises: [session1, session2])])
        let trend = try #require(trends.first { $0.exerciseID == squat })
        #expect(trend.points.count == 2)
        #expect(trend.points.map(\.date) == [earlier, later])
        #expect(trend.points.map(\.topLoad) == [
            Mass(value: 60, unit: .kilograms), Mass(value: 80, unit: .kilograms),
        ])
    }

    @Test("An exercise with no logged sets produces no trend")
    func exerciseWithNoLoggedSetsIsExcluded() {
        let neverLogged = exercise(id: ExerciseID(rawValue: "never-logged"), sets: [])
        // An incomplete/warmup set doesn't count toward `completedWorkingSets`
        // either, so this exercise should also be excluded.
        let onlyWarmedUp = PlannedExercise(
            exerciseID: ExerciseID(rawValue: "only-warmed-up"), displayName: "Deadlift",
            order: 1, targetSets: 1, repRange: "5", restSeconds: 180
        )
        onlyWarmedUp.loggedSets = [
            LoggedSet(setIndex: 0, load: Mass(value: 60, unit: .kilograms), reps: 5, isCompleted: true, isWarmup: true),
        ]

        let trends = ExerciseTrend.build(from: [plan(exercises: [neverLogged, onlyWarmedUp])])
        #expect(trends.isEmpty)
    }

    // MARK: - Work that is not counted in repetitions

    /// **A hold has no load and no reps, so the first two terms of the ranking
    /// are equal for every set of it.** Without the seconds term the "top set"
    /// of a plank session is whichever set the ordering happened to leave last,
    /// which is a figure with no meaning shown on a chart labelled *heaviest
    /// set*.
    @Test("The top set of a session of holds is the longest one")
    func theLongestHoldIsTheTopSet() throws {
        let plank = ExerciseID(rawValue: "front-plank")
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let trends = ExerciseTrend.build(from: [
            plan(exercises: [
                exercise(
                    id: plank,
                    sets: [
                        heldSet(30, at: day, setIndex: 0),
                        heldSet(75, at: day, setIndex: 1),
                        heldSet(45, at: day, setIndex: 2),
                    ])
            ])
        ])
        let point = try #require(trends.first { $0.exerciseID == plank }?.points.first)

        #expect(point.topDurationSeconds == 75)
        #expect(point.topLoad == nil, "nothing was on the bar")
        #expect(point.topReps == 0, "and nothing was counted")
    }

    @Test("The top set of a session of carries is the furthest one")
    func theFurthestCarryIsTheTopSet() throws {
        let carry = ExerciseID(rawValue: "kettlebell-farmers-carry")
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let trends = ExerciseTrend.build(from: [
            plan(exercises: [
                exercise(
                    id: carry,
                    sets: [
                        carriedSet(40, at: day, setIndex: 0),
                        carriedSet(38, at: day, setIndex: 1),
                        carriedSet(52, at: day, setIndex: 2),
                    ])
            ])
        ])
        let point = try #require(trends.first { $0.exerciseID == carry }?.points.first)

        #expect(point.topDistance?.value == 52)
        #expect(point.topDistance?.unit == .metres, "in the unit it was logged in")
        #expect(point.topDurationSeconds == nil, "it was not a hold")
    }

    @Test("A carry keeps the unit it was logged in rather than being converted")
    func aCarriedDistanceIsNotConverted() throws {
        let sled = ExerciseID(rawValue: "sled-push")
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let yards = LoggedSet(
            setIndex: 0, load: nil, reps: 0,
            distance: Distance(value: 20, unit: .yards),
            isCompleted: true, isWarmup: false, completedAt: day)
        let trends = ExerciseTrend.build(from: [
            plan(exercises: [exercise(id: sled, sets: [yards])])
        ])
        let point = try #require(trends.first { $0.exerciseID == sled }?.points.first)

        // Twenty yards is not eighteen point three metres here or anywhere:
        // nothing in this project converts a distance.
        #expect(point.topDistance == Distance(value: 20, unit: .yards))
    }
}
