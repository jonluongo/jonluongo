import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// The store's side of knowing what day it is: turning a stored block into the
/// values `BlockCalendar` reads, and finding the stored session back again.
///
/// The derivation itself is tested in `LiftingKit`, without a simulator. What
/// is tested here is only what touches SwiftData — chiefly the two judgements
/// the store makes about a session: whether it is finished, and whether it has
/// been started.
@Suite("Today in plan")
struct TodayInPlanTests {

    private static let monday = Date(timeIntervalSince1970: 1_772_409_600)  // 2026-03-02 UTC

    // MARK: - Session progress

    @Test("A session nobody has opened has not been started")
    func untouchedSessionIsNotStarted() {
        let day = WorkoutDay(weekday: .monday, focus: "Push")
        #expect(TodayInPlan.progress(of: day) == .notStarted)
    }

    @Test("Rows the logging screen seeded are not work, so the session is still not started")
    func seededRowsAreNotProgress() {
        // Opening the workout writes a row for every prescribed set before the
        // lifter touches anything. Existence would call that session started;
        // it is not.
        let day = WorkoutDay(weekday: .monday, focus: "Push")
        let exercise = PlannedExercise(displayName: "Bench Press", targetSets: 3, repRange: "5")
        exercise.loggedSets = (0..<3).map { LoggedSet(setIndex: $0, isCompleted: false) }
        day.exercises = [exercise]

        #expect(TodayInPlan.progress(of: day) == .notStarted)
    }

    @Test("One ticked set is a session in progress")
    func tickedSetIsInProgress() {
        let day = WorkoutDay(weekday: .monday, focus: "Push")
        let exercise = PlannedExercise(displayName: "Bench Press", targetSets: 3, repRange: "5")
        exercise.loggedSets = [
            LoggedSet(setIndex: 0, reps: 5, isCompleted: true),
            LoggedSet(setIndex: 1, isCompleted: false),
        ]
        day.exercises = [exercise]

        #expect(TodayInPlan.progress(of: day) == .inProgress)
    }

    @Test("A ticked warmup counts: the lifter is in the gym")
    func tickedWarmupIsInProgress() {
        let day = WorkoutDay(weekday: .monday, focus: "Push")
        let exercise = PlannedExercise(displayName: "Bench Press", targetSets: 3, repRange: "5")
        exercise.loggedSets = [LoggedSet(setIndex: 0, reps: 8, isCompleted: true, isWarmup: true)]
        day.exercises = [exercise]

        #expect(TodayInPlan.progress(of: day) == .inProgress)
    }

    @Test("A finished session reports the date it was finished on")
    func finishedSession() {
        let finished = Self.monday.addingTimeInterval(3_600)
        let day = WorkoutDay(weekday: .monday, focus: "Push", completedAt: finished)
        let exercise = PlannedExercise(displayName: "Bench Press", targetSets: 3, repRange: "5")
        exercise.loggedSets = [LoggedSet(setIndex: 0, reps: 5, isCompleted: true)]
        day.exercises = [exercise]

        #expect(TodayInPlan.progress(of: day) == .finished(finished))
    }

    // MARK: - The schedule a plan states

    @Test("A block's schedule states its start, its weeks and its sessions")
    func scheduleFromPlan() throws {
        let plan = Self.fourWeekPlan()
        let schedule = TodayInPlan.schedule(for: plan)

        #expect(schedule.startDate == Self.monday)
        #expect(schedule.closedAt == nil)
        #expect(schedule.weeks.map(\.ordinal) == [1, 2, 3, 4])
        let deload = try #require(schedule.weeks.last)
        #expect(deload.label == "Deload")
        #expect(deload.isDeload)
        #expect(deload.days.map(\.weekday) == [.monday, .wednesday, .friday])
        #expect(deload.days.map(\.focus) == ["Push", "Pull", "Legs"])
    }

    @Test("A superseded block is a closed block, because that is all the record says")
    func supersededPlanIsClosed() {
        // `PlanImporter` writes `completedAt` on the old block when a new one
        // arrives. The record does not distinguish that from finishing it, and
        // neither does the schedule.
        let plan = Self.fourWeekPlan()
        plan.completedAt = Self.monday.addingTimeInterval(86_400)

        let today = TodayInPlan.resolve(
            plan, on: Self.monday.addingTimeInterval(86_400 * 8), calendar: Self.utc)
        #expect(today.standing == .closed(on: plan.completedAt ?? .distantPast))
    }

    // MARK: - Resolving and looking back up

    @Test("A stored block answers which week and which session today is")
    func resolveOverAStoredBlock() throws {
        let context = ModelContext(try StoreContainer.inMemory())
        let plan = Self.fourWeekPlan()
        context.insert(plan)
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<TrainingPlan>()).first)
        // Wednesday of week 2 — nine days after Monday 2 March.
        let today = TodayInPlan.resolve(
            loaded, on: Self.monday.addingTimeInterval(86_400 * 9 + 3_600 * 12),
            calendar: Self.utc)

        let session = try #require(today.standing.session)
        #expect(session.week.ordinal == 2)
        #expect(session.week.totalWeeks == 4)
        #expect(session.weekday == .wednesday)
        #expect(session.focus == "Pull")

        // And the stored row is findable again from the answer.
        let stored = try #require(TodayInPlan.session(session, in: loaded))
        #expect(stored.weekday == .wednesday)
        #expect(stored.focus == "Pull")
        #expect(stored.week?.ordinal == 2)
    }

    @Test("A session the block does not prescribe is not found rather than guessed at")
    func lookupOfAnAbsentSession() throws {
        let plan = Self.fourWeekPlan()
        let absent = BlockDay(
            week: WeekPlacement(ordinal: 9, totalWeeks: 4, stated: nil),
            weekday: .sunday, focus: "", date: Self.monday, progress: .notStarted)

        #expect(TodayInPlan.session(absent, in: plan) == nil)
    }

    @Test("A stored session answers the calendar day it falls on")
    func dateOfAStoredSession() throws {
        // The block screen holds a week and a weekday and has to hand the front
        // door a date, because the front door is addressed by date. The answer
        // has to be the same one `resolve` would give, or tapping a session in
        // the block would show a different day.
        let context = ModelContext(try StoreContainer.inMemory())
        let plan = Self.fourWeekPlan()
        context.insert(plan)
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<TrainingPlan>()).first)
        let week = try #require(loaded.orderedWeeks.first { $0.ordinal == 2 })
        let wednesday = try #require(week.orderedDays.first { $0.weekday == .wednesday })

        let date = try #require(TodayInPlan.date(of: wednesday, calendar: Self.utc))
        // Wednesday of week 2 is nine days after Monday 2 March.
        #expect(date == Self.utc.startOfDay(for: Self.monday.addingTimeInterval(9 * 86_400)))

        let standing = TodayInPlan.resolve(loaded, on: date, calendar: Self.utc).standing
        let session = try #require(standing.session)
        #expect(TodayInPlan.session(session, in: loaded) === wednesday)
    }

    @Test("A session no block holds has no date rather than a substitute one")
    func dateOfADetachedSession() {
        #expect(TodayInPlan.date(of: WorkoutDay(weekday: .monday), calendar: Self.utc) == nil)
    }

    // MARK: - The days the strip may show

    @Test("A live block offers every one of its days")
    func selectableDaysCoverTheBlock() throws {
        let span = try #require(
            TodayInPlan.selectableDays(in: Self.fourWeekPlan(), calendar: Self.utc))

        #expect(span.lowerBound == Self.utc.startOfDay(for: Self.monday))
        // Four weeks from Monday 2 March ends on Sunday 29 March.
        #expect(span.upperBound
            == Self.utc.startOfDay(for: Self.monday.addingTimeInterval(27 * 86_400)))
    }

    @Test("A closed block offers no day to choose")
    func closedBlockHasNoSelectableDays() {
        // Every date reports the block closed, so a strip over it would be a
        // control that changes nothing.
        let plan = Self.fourWeekPlan()
        plan.completedAt = Self.monday

        #expect(TodayInPlan.selectableDays(in: plan, calendar: Self.utc) == nil)
    }

    @Test("A block that prescribes no weeks offers no day to choose")
    func unscheduledBlockHasNoSelectableDays() {
        // The store always carries a start date, so this is the one shape of
        // block a day cannot be placed against: nothing to measure from it.
        let unscheduled = TrainingPlan(
            title: "Unscheduled", startDate: Self.monday, weekdays: [])
        unscheduled.weeks = []

        #expect(TodayInPlan.selectableDays(in: unscheduled, calendar: Self.utc) == nil)
    }

    @Test("Every day the strip may show reads as something rather than blank")
    func everySelectableDayResolves() throws {
        // The property that stops a swipe reaching an empty screen.
        let plan = Self.fourWeekPlan()
        let span = try #require(TodayInPlan.selectableDays(in: plan, calendar: Self.utc))

        for offset in 0..<28 {
            let date = Self.monday.addingTimeInterval(Double(offset) * 86_400)
            #expect(span.contains(Self.utc.startOfDay(for: date)))
            let standing = TodayInPlan.resolve(plan, on: date, calendar: Self.utc).standing
            #expect(standing.session != nil || standing.rest != nil)
        }
    }

    // MARK: - What the strip marks

    @Test("A day the block trains on is marked, and a rest day is not")
    func marksTrainingDays() {
        let plan = Self.fourWeekPlan()
        let calendar = Self.utc

        // Monday, Wednesday and Friday of week 1 train; the rest do not.
        #expect(TodayInPlan.prescribesSession(in: plan, on: Self.monday, calendar: calendar))
        #expect(TodayInPlan.prescribesSession(
            in: plan, on: Self.monday.addingTimeInterval(2 * 86_400), calendar: calendar))
        #expect(TodayInPlan.prescribesSession(
            in: plan, on: Self.monday.addingTimeInterval(4 * 86_400), calendar: calendar))

        #expect(!TodayInPlan.prescribesSession(
            in: plan, on: Self.monday.addingTimeInterval(86_400), calendar: calendar))
        #expect(!TodayInPlan.prescribesSession(
            in: plan, on: Self.monday.addingTimeInterval(6 * 86_400), calendar: calendar))
    }

    @Test("A day outside the block is not marked")
    func marksNothingOutsideTheBlock() {
        let plan = Self.fourWeekPlan()

        #expect(!TodayInPlan.prescribesSession(
            in: plan, on: Self.monday.addingTimeInterval(-86_400), calendar: Self.utc))
        #expect(!TodayInPlan.prescribesSession(
            in: plan, on: Self.monday.addingTimeInterval(28 * 86_400), calendar: Self.utc))
    }

    // MARK: - Fixtures

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // Confined to tests: a constant identifier this file owns.
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Four weeks from Monday 2 March 2026, training Monday, Wednesday, Friday.
    private static func fourWeekPlan() -> TrainingPlan {
        let plan = TrainingPlan(
            title: "Four-week block", startDate: monday, weekCount: 4,
            weekdays: [.monday, .wednesday, .friday])
        let focuses: [(Weekday, String)] = [(.monday, "Push"), (.wednesday, "Pull"), (.friday, "Legs")]
        plan.weeks = (1...4).map { ordinal in
            let week = TrainingWeek(
                ordinal: ordinal,
                label: ordinal == 4 ? "Deload" : "Accumulation",
                isDeload: ordinal == 4)
            week.days = focuses.map { WorkoutDay(weekday: $0.0, focus: $0.1) }
            return week
        }
        return plan
    }
}
