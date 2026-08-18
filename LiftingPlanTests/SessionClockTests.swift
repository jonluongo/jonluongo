import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// When the logging screen's clock says training began.
///
/// It used to count from the moment the screen opened, so closing a session and
/// resuming it restarted the clock — it was timing the sheet rather than the
/// workout. The anchor is now a fact the record already holds, which is what
/// makes it survive closing, backgrounding and syncing without anything new
/// being stored. These assert that it is anchored to evidence of training and to
/// nothing else.
@Suite("The session clock")
struct SessionClockTests {

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    /// 2026-03-02 08:00 UTC.
    private static let eight = Date(timeIntervalSince1970: 1_772_438_400)

    /// A day holding one exercise with `sets` rows on it, built in a live
    /// context so the relationships behave as they do in the app.
    private func day(sets: [LoggedSet]) throws -> WorkoutDay {
        let context = try context()
        let day = WorkoutDay(weekday: .monday, focus: "Push")
        let exercise = PlannedExercise(
            exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
            displayName: "Barbell Bench Press",
            order: 0, targetSets: sets.count, repRange: "5")
        context.insert(day)
        context.insert(exercise)
        exercise.day = day
        for set in sets {
            context.insert(set)
            set.exercise = exercise
        }
        try context.saveOrThrow()
        return day
    }

    private func set(_ index: Int, completed: Bool, at date: Date, warmup: Bool = false) -> LoggedSet {
        LoggedSet(
            setIndex: index, load: Mass(value: 135, unit: .pounds), reps: 5,
            isCompleted: completed, isWarmup: warmup, completedAt: date)
    }

    @Test("A session nobody has trained has no start")
    func noTickedSetHasNoStart() throws {
        // Rows exist the moment the screen is opened — seeding writes one per
        // prescribed set — so rows are evidence a screen was opened, not that
        // anything was lifted. A clock here would be timing how long he looked
        // at his phone.
        let day = try day(sets: [
            set(0, completed: false, at: Self.eight),
            set(1, completed: false, at: Self.eight),
        ])

        #expect(day.startedAt == nil)
    }

    @Test("Training began at the earliest ticked set, not the latest")
    func startsAtTheFirstTickedSet() throws {
        let day = try day(sets: [
            set(0, completed: true, at: Self.eight),
            set(1, completed: true, at: Self.eight.addingTimeInterval(300)),
            set(2, completed: false, at: Self.eight.addingTimeInterval(600)),
        ])

        #expect(day.startedAt == Self.eight)
    }

    @Test("The order rows are stored in does not decide when training began")
    func earliestWinsRegardlessOfRowOrder() throws {
        // SwiftData does not guarantee relationship ordering, so the answer has
        // to come from the timestamps rather than from whichever row comes back
        // first.
        let day = try day(sets: [
            set(0, completed: true, at: Self.eight.addingTimeInterval(600)),
            set(1, completed: true, at: Self.eight),
        ])

        #expect(day.startedAt == Self.eight)
    }

    @Test("A warm-up counts: he is in the gym")
    func warmupStartsTheClock() throws {
        let day = try day(sets: [
            set(0, completed: true, at: Self.eight, warmup: true),
            set(1, completed: true, at: Self.eight.addingTimeInterval(300)),
        ])

        #expect(day.startedAt == Self.eight)
    }

    @Test("An unticked set's stamp is not mistaken for a start")
    func untickedStampsAreIgnored() throws {
        // `completedAt` is not optional and defaults to the moment the row was
        // created, so every seeded row carries a plausible-looking date. Only
        // `isCompleted` separates a set that happened from one that was drawn.
        let day = try day(sets: [
            set(0, completed: false, at: Self.eight),
            set(1, completed: true, at: Self.eight.addingTimeInterval(300)),
        ])

        #expect(day.startedAt == Self.eight.addingTimeInterval(300))
    }
}

/// What the finish control is told about a session that is not filled in.
///
/// The count decides a colour and a question, never a permission: finishing a
/// session with sets left is the lifter's to do, and often the right thing.
@Suite("Unlogged sets")
struct UnloggedSetTests {

    private func day(completed: [Bool]) throws -> WorkoutDay {
        let context = ModelContext(try StoreContainer.inMemory())
        let day = WorkoutDay(weekday: .monday, focus: "Push")
        let exercise = PlannedExercise(
            exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
            displayName: "Barbell Bench Press", order: 0,
            targetSets: completed.count, repRange: "5")
        context.insert(day)
        context.insert(exercise)
        exercise.day = day
        for (index, isCompleted) in completed.enumerated() {
            let set = LoggedSet(setIndex: index, reps: 5, isCompleted: isCompleted)
            context.insert(set)
            set.exercise = exercise
        }
        try context.saveOrThrow()
        return day
    }

    @Test("A session filled in has nothing left")
    func fullyLogged() throws {
        #expect(try day(completed: [true, true, true]).unloggedSetCount == 0)
    }

    @Test("What is left is counted exactly, not reported as some")
    func countsWhatIsLeft() throws {
        // One set short and nine sets short are different questions to ask.
        #expect(try day(completed: [true, false, false]).unloggedSetCount == 2)
    }

    @Test("A session nobody has started is entirely unlogged")
    func nothingTicked() throws {
        #expect(try day(completed: [false, false]).unloggedSetCount == 2)
    }

    @Test("A session with no rows has nothing outstanding")
    func noRows() throws {
        #expect(try day(completed: []).unloggedSetCount == 0)
    }
}
