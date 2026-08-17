import Foundation
import LiftingKit

/// What the Plans list says about one plan: the dates it covers, what to call
/// it, whether it is the current one, and how much of it has been logged.
///
/// **What it does.** Turns a stored `TrainingPlan` into the three strings the
/// list draws. It derives nothing about training and invents nothing that is
/// missing: a block the app cannot place on a calendar gets no dates rather than
/// plausible ones, and a block with no sessions says so rather than reporting
/// zero of zero logged.
///
/// **How it is used.** `PlansView` calls `header(for:)` for a section's date
/// range, and `title(of:)` and `summary(of:)` for the card inside it. It is a
/// plain enum of static functions, separate from the view, so the phrasing is
/// testable without a simulator — the same reason `PlanWeekSelection` and
/// `TodayPhrasing` are.
///
/// **What it depends on.** `TrainingPlan` from Store, `TodayInPlan` from
/// Services for the block's schedule, and `BlockCalendar` from LiftingKit for
/// the arithmetic that turns a start date and a week count into a span. The
/// span rule is not restated here — a block runs seven days per week from its
/// start date, and that sentence lives in exactly one place.
enum PlansListing {

    /// What the plan called itself, or what it is for when it went unnamed.
    ///
    /// The same answer the plan's own screen uses for its navigation title, so
    /// tapping a card cannot land on a screen with a different name on it.
    static func title(of plan: TrainingPlan) -> String {
        if !plan.title.isEmpty { return plan.title }
        if !plan.goal.isEmpty { return plan.goal }
        return "Plan"
    }

    /// The first and last day this block covers, or `nil` when nothing places
    /// it on a calendar.
    ///
    /// Whether the record has closed the block is deliberately not consulted: a
    /// superseded block still covered the days it covered, and a list of past
    /// blocks that refused to date them would be a list of anonymous rows.
    static func span(of plan: TrainingPlan, calendar: Calendar = .current) -> ClosedRange<Date>? {
        BlockCalendar(calendar: calendar).span(of: TodayInPlan.schedule(for: plan))
    }

    /// A section's heading: the plan's timeframe, or the fact that it has none.
    ///
    /// A block with no weeks cannot be measured, and the honest heading for it
    /// says that rather than showing a start date as though it were a range or
    /// a range as though a week had been stated.
    static func header(
        for plan: TrainingPlan,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        dateRange(of: plan, calendar: calendar, locale: locale) ?? "No dates yet"
    }

    /// `"Aug 17 – Sep 13, 2026"`, or `nil` when the block cannot be placed.
    static func dateRange(
        of plan: TrainingPlan,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        guard let span = span(of: plan, calendar: calendar) else { return nil }
        var style = Date.IntervalFormatStyle(date: .abbreviated, time: .omitted)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale
        return style.format(span.lowerBound..<span.upperBound)
    }

    /// Whether this is the block the lifter is on.
    ///
    /// `completedAt` is what the record has: it is written both when a lifter
    /// finishes a block and when a later import supersedes one, and an import
    /// closes every open block before inserting the new one. So exactly one
    /// plan is open at a time, and none is once the last block has ended —
    /// which is the truthful answer on that day, not a gap to be filled.
    static func isCurrent(_ plan: TrainingPlan) -> Bool { plan.completedAt == nil }

    /// `"Current · 12 sessions · 6 logged"`, dropping each part that has
    /// nothing to state.
    ///
    /// The word carries which block is live, not a colour and not a badge —
    /// the same construction the week rows inside a block already use for
    /// "This week". A block with no sessions says so; it never claims zero of
    /// zero, and a block nobody has trained yet does not report "0 logged",
    /// because that is a number about the lifter rather than about the plan.
    static func summary(of plan: TrainingPlan) -> String {
        var parts: [String] = []
        if isCurrent(plan) { parts.append("Current") }
        let days = plan.orderedWeeks.flatMap(\.orderedDays)
        if days.isEmpty {
            parts.append("No sessions yet")
        } else {
            parts.append("\(days.count) session\(days.count == 1 ? "" : "s")")
            let logged = days.filter { $0.completedAt != nil }.count
            if logged > 0 { parts.append("\(logged) logged") }
        }
        return parts.joined(separator: " · ")
    }
}
