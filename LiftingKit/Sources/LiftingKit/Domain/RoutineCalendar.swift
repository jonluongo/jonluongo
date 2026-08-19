import Foundation

/// The days a training block covers.
///
/// **What it does.** Turns a block's start date and its week ordinals into the
/// range of calendar days it runs across. It reports and never advises: the
/// extent is arithmetic, and what to say about it is the caller's.
///
/// **How it is used.** Build one with the lifter's calendar and ask it for a
/// `RoutineSchedule`'s span. The calendar is an argument rather than a global,
/// which is what lets the derivation be tested without a simulator, a database,
/// or a particular machine's time zone.
///
/// **It used to answer where today falls** — which week, whether today trains,
/// what is next — for a front door that no longer exists. The app reads the
/// week the lifter is on off the record instead, because a session trained on
/// Wednesday that was written for Tuesday is still that session; see
/// `docs/decided.md`. Dating the block he is *training* was rejected outright.
/// What survived is the one question still asked: a block behind him is dated,
/// and this is what dates it.
///
/// **What it depends on.** Foundation's `Calendar` and `RoutineSchedule`.
/// Nothing persistent, nothing visual.
///
/// ## How a date is anchored
///
/// **A week is seven days from the block's start date, not a calendar week.**
/// Week 1 covers the start date and the six days after it, week 2 the seven
/// after that, and so on.
///
/// This is a stated assumption, and it is the one that loses nothing. Anchoring
/// instead to the calendar week containing the start date would put part of
/// week 1 before the block began — a Monday session on a block imported on
/// Wednesday would be in the past on arrival. It would also depend on
/// `Calendar.firstWeekday`, a locale setting, so the same plan would mean
/// different dates for two lifters in different regions. Seven days from the
/// start date has neither problem, and consecutive weeks are exactly seven days
/// apart.
///
/// Both ends are `calendar.startOfDay(for:)`, so the day rolls at the lifter's
/// own midnight, in the time zone their calendar carries. Because the
/// arithmetic goes through the calendar rather than through seconds, a week
/// that gains or loses an hour to daylight saving is still seven days.
public struct RoutineCalendar: Sendable {

    /// The calendar the answer is derived in — crucially, the time zone it
    /// carries. The app passes `.current`; tests pass a fixed one.
    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// The first and last calendar day this block covers, or `nil` when nothing
    /// places it on a calendar — no start date, or no weeks to measure.
    ///
    /// A block runs seven days per week from its start date, so a four-week
    /// block covers its start date and the twenty-seven days after it.
    /// **Whether the record has closed the block is not consulted** — a closed
    /// block still covered the days it covered, and what to do about that is
    /// the caller's decision, not this one's.
    public func span(of schedule: RoutineSchedule) -> ClosedRange<Date>? {
        guard
            let startDate = schedule.startDate,
            let totalWeeks = schedule.weekOrdinals.max(),
            totalWeeks > 0
        else { return nil }
        let start = calendar.startOfDay(for: startDate)
        guard let end = calendar.date(
            byAdding: .day, value: totalWeeks * 7 - 1, to: start
        ) else { return nil }
        return start...end
    }
}
