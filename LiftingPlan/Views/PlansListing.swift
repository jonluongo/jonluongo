import Foundation
import LiftingKit

/// What the Blocks list says about one block: where it stands, what to call it,
/// the dates it covers, and how much of it has been logged.
///
/// **What it does.** Turns a stored `TrainingPlan` into the strings the list
/// draws. It derives nothing about training and invents nothing that is
/// missing: a block the app cannot place on a calendar gets no dates rather than
/// plausible ones, and a block with no sessions says so rather than reporting
/// zero of zero logged.
///
/// **How it is used.** `PlansView` calls `standing(of:)` to group the list,
/// `title(of:)` for a card's name and `subtitle(of:)` for the line under it. It
/// is a plain enum of static functions, separate from the view, so the phrasing
/// is testable without a simulator — the same reason `PlanWeekSelection` and
/// `TodayPhrasing` are. Colour is deliberately not here: a standing knows the
/// word it is said with, and the view decides what tint follows it.
///
/// **What it depends on.** `TrainingPlan` from Store, `TodayInPlan` from
/// Services for the block's schedule, and `BlockCalendar` from LiftingKit for
/// the arithmetic that turns a start date and a week count into a span. The
/// span rule is not restated here — a block runs seven days per week from its
/// start date, and that sentence lives in exactly one place.
enum PlansListing {

    /// Where a block stands: the one being trained, or one behind him.
    ///
    /// The record holds no more than this. `completedAt` is written both when a
    /// lifter finishes a block and when a later import supersedes one, so
    /// "finished" and "abandoned" are the same value in the database and the
    /// list refuses to tell them apart. Neither is a verdict: an earlier block
    /// is where the training went, not a failure, and nothing here reads as a
    /// score, a streak, or a grade.
    enum Standing {

        /// The block the lifter is on. There is at most one.
        case current

        /// A block the record has closed. Everything before the current one.
        case earlier

        /// The heading the list groups under. The word carries the difference;
        /// the tint only follows it.
        var heading: String {
            switch self {
            case .current: "Current"
            case .earlier: "Earlier"
            }
        }

        /// The same fact said into a row's own label. A section heading is a
        /// separate element to a screen reader, so a card read on its own would
        /// otherwise be a name and a date with no standing at all.
        var spoken: String {
            switch self {
            case .current: "Current block"
            case .earlier: "Earlier block"
            }
        }
    }

    /// Where this block stands.
    ///
    /// An import closes every open block before inserting the new one, so
    /// exactly one is open at a time — and none is once the last block has
    /// ended, which is the truthful answer on that day rather than a gap to be
    /// filled.
    static func standing(of plan: TrainingPlan) -> Standing {
        plan.completedAt == nil ? .current : .earlier
    }

    /// What the block called itself, or what it is for when it went unnamed.
    ///
    /// The same answer the block's own screen uses for its navigation title, so
    /// tapping a card cannot land on a screen with a different name on it.
    static func title(of plan: TrainingPlan) -> String {
        if !plan.title.isEmpty { return plan.title }
        if !plan.goal.isEmpty { return plan.goal }
        return "Block"
    }

    /// The first and last day this block covers, or `nil` when nothing places
    /// it on a calendar.
    ///
    /// Whether the record has closed the block is deliberately not consulted: an
    /// earlier block still covered the days it covered, and a list of past
    /// blocks that refused to date them would be a list of anonymous rows.
    static func span(of plan: TrainingPlan, calendar: Calendar = .current) -> ClosedRange<Date>? {
        BlockCalendar(calendar: calendar).span(of: TodayInPlan.schedule(for: plan))
    }

    /// The block's timeframe, or the fact that it has none.
    ///
    /// A block with no weeks cannot be measured, and the honest line for it says
    /// that rather than showing a start date as though it were a range or a
    /// range as though a week had been stated.
    static func dates(
        of plan: TrainingPlan,
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

    /// `"12 sessions · 6 logged"`, dropping each part that has nothing to state.
    ///
    /// A block with no sessions says so; it never claims zero of zero, and a
    /// block nobody has trained yet does not report "0 logged", because that is
    /// a number about the lifter rather than about the block.
    static func summary(of plan: TrainingPlan) -> String {
        var parts: [String] = []
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

    /// The whole line under a card's name: `"Aug 17 – Sep 13, 2026 · 12
    /// sessions · 6 logged"`.
    ///
    /// The dates were the heading of a section per block, back when every block
    /// was its own section. The list now groups by standing instead, so the
    /// dates belong to the card they describe.
    static func subtitle(
        of plan: TrainingPlan,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        "\(dates(of: plan, calendar: calendar, locale: locale)) · \(summary(of: plan))"
    }
}
