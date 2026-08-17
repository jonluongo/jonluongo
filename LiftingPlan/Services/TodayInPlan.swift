import Foundation
import LiftingKit

/// The store's side of knowing what day it is.
///
/// **What it does.** Reads a stored `TrainingPlan` into the plain values
/// `BlockCalendar` places on a calendar, asks it where today falls, and finds
/// the stored session back again from the answer. The arithmetic — which week,
/// which day, what is next — is not here; it lives in `LiftingKit`, where it is
/// tested without a simulator or a database. What is here is the one thing that
/// genuinely needs the store: reading how far a session has got.
///
/// **How it is used.** The front door calls `resolve(_:on:calendar:)` with the
/// current date and the lifter's calendar, switches on the standing it gets
/// back, and calls `session(_:in:)` when it needs the row to open. Nothing is
/// written; this only answers.
///
/// **What it depends on.** `TrainingPlan`, `TrainingWeek`, `WorkoutDay` and
/// `LoggedSet` from Store, and `BlockCalendar` from LiftingKit.
enum TodayInPlan {

    /// Where `now` falls in this block, and what it prescribes next.
    ///
    /// The calendar is an argument, and the app passes `.current` so the day
    /// rolls at the lifter's own midnight rather than at UTC's.
    static func resolve(
        _ plan: TrainingPlan, on now: Date, calendar: Calendar = .current
    ) -> TodayInBlock {
        BlockCalendar(calendar: calendar).today(in: schedule(for: plan), on: now)
    }

    /// The days of this block a lifter may choose between, or `nil` when there
    /// is nothing to choose.
    ///
    /// The week strip lets any day be selected, so something has to say which
    /// days are the block's. Three blocks answer `nil`, and for the same reason
    /// in each: **every day reads the same, so choosing between them is a
    /// gesture that changes nothing.** A block with no start date or no weeks
    /// cannot place a day at all, and a block the record has closed reports
    /// itself closed on every date it is asked about. A strip over any of them
    /// would be a control that does nothing, which is worse than no control.
    static func selectableDays(
        in plan: TrainingPlan, calendar: Calendar = .current
    ) -> ClosedRange<Date>? {
        guard plan.completedAt == nil else { return nil }
        return BlockCalendar(calendar: calendar).span(of: schedule(for: plan))
    }

    /// Whether the block prescribes a session on this date.
    ///
    /// What the strip's mark under a day means, and nothing more: it is the same
    /// question `resolve` answers, asked of a day the lifter is not standing in.
    /// A day the block prescribes nothing on is unmarked, which is how the shape
    /// of the training week is read at a glance.
    static func prescribesSession(
        in plan: TrainingPlan, on date: Date, calendar: Calendar = .current
    ) -> Bool {
        resolve(plan, on: date, calendar: calendar).standing.session != nil
    }

    /// This block reduced to the values a calendar question needs.
    ///
    /// `completedAt` travels through as `closedAt` and nothing more is claimed
    /// about it: the field carries both "the lifter finished this block" and
    /// "a later block superseded it", because `PlanImporter` writes it in the
    /// second case too. The record never separated the two, so nothing here
    /// invents the difference.
    static func schedule(for plan: TrainingPlan) -> BlockSchedule {
        BlockSchedule(
            startDate: plan.startDate,
            closedAt: plan.completedAt,
            weeks: plan.orderedWeeks.map { week in
                ScheduledWeek(
                    ordinal: week.ordinal,
                    label: week.label,
                    isDeload: week.isDeload,
                    days: week.orderedDays.map { day in
                        ScheduledDay(
                            weekday: day.weekday, focus: day.focus, progress: progress(of: day))
                    }
                )
            }
        )
    }

    /// How far the lifter has got with one stored session.
    ///
    /// **Finished is `completedAt`**, which the logging screen writes when the
    /// lifter finishes and nothing else writes at all. Unlike the same-named
    /// field on `TrainingPlan`, this one carries no second meaning: an import
    /// supersedes blocks, never days.
    ///
    /// **In progress is one ticked set.** Existence of rows will not do —
    /// opening the logging screen seeds a row for every set the plan
    /// prescribed, so rows are evidence that a screen was opened rather than
    /// that anything was lifted. A ticked set, warmup included, is the earliest
    /// point at which the lifter is demonstrably in the gym, and it is what
    /// separates "Start" from "Resume".
    static func progress(of day: WorkoutDay) -> SessionProgress {
        if let completedAt = day.completedAt {
            return .finished(completedAt)
        }
        let hasLoggedWork = (day.exercises ?? []).contains { exercise in
            (exercise.loggedSets ?? []).contains { $0.isCompleted }
        }
        return hasLoggedWork ? .inProgress : .notStarted
    }

    /// The stored session an answer refers to, or `nil` when the block holds
    /// none at that position.
    ///
    /// The answer travels as a week ordinal and a weekday rather than as a
    /// record, which is what keeps the derivation free of the store. This is
    /// the lookup back, and it finds nothing rather than guessing when the
    /// block has moved on underneath it.
    /// The calendar day a stored session falls on, or `nil` when nothing
    /// places it — a session outside a week, a week outside a block, or a block
    /// with no start date.
    ///
    /// The lookup `session(_:in:)` performs, run the other way. It is what lets
    /// the block screen hand a day to the screen that shows days instead of
    /// opening a second screen to show the same session: the block knows a week
    /// and a weekday, and the front door is addressed by date.
    static func date(of day: WorkoutDay, calendar: Calendar = .current) -> Date? {
        guard let week = day.week, let plan = week.plan else { return nil }
        return BlockCalendar(calendar: calendar)
            .date(ofWeek: week.ordinal, weekday: day.weekday, in: schedule(for: plan))
    }

    static func session(_ day: BlockDay, in plan: TrainingPlan) -> WorkoutDay? {
        plan.orderedWeeks
            .first { $0.ordinal == day.week.ordinal }?
            .orderedDays
            .first { $0.weekday == day.weekday }
    }
}
