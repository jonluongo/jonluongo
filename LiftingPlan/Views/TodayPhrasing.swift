import Foundation
import LiftingKit

/// The words the front door says about a day.
///
/// **What it does.** Turns the values `BlockCalendar` answers with — a week's
/// placement, a prescribed day, how far a session has got — into the short
/// strings the Today screen prints. It states facts and never advises: "Rest
/// day", "Thursday · Push", "Starts in 3 days" are all readings of a calendar
/// and a stored plan, and what the lifter should do about any of them is not
/// decided here.
///
/// **How it is used.** `TodayView` calls it for every line that is not a stored
/// string. It lives apart from the view because a sentence with a plural and an
/// off-by-one in it is worth testing, and testing it through a `List` would
/// need a simulator to assert what a `String` already answers.
///
/// **What it depends on.** `WeekPlacement`, `BlockDay`, `SessionProgress` and
/// `Weekday` from LiftingKit, and Foundation's `Calendar`. No store, no view,
/// no state.
enum TodayPhrasing {

    /// `"Week 2 of 4 · Accumulation"` — where this week sits and what the plan
    /// called it.
    ///
    /// A one-week block is not "of 1", a week the plan named nothing states its
    /// position alone, and a deload the plan left unlabelled is still said to
    /// be one rather than losing the only thing that distinguishes it.
    static func weekLine(_ placement: WeekPlacement) -> String {
        let position = placement.totalWeeks > 1
            ? "Week \(placement.ordinal) of \(placement.totalWeeks)"
            : "Week \(placement.ordinal)"
        guard let stated = placement.stated else { return position }
        if !stated.label.isEmpty { return "\(position) · \(stated.label)" }
        if stated.isDeload { return "\(position) · Deload" }
        return position
    }

    /// What to call today's session: what the plan said it is for, or the day
    /// it falls on when the plan named it nothing.
    static func sessionTitle(_ day: BlockDay) -> String {
        day.focus.isEmpty ? day.weekday.fullName : day.focus
    }

    /// The word on the button, or `nil` when the session is finished and there
    /// is nothing left to press.
    /// The word on the button.
    ///
    /// A finished session still opens. It used to return nothing here, which
    /// left a logged day with no door: a mis-tapped Finish, a weight typed
    /// wrong, or a set done after the lifter thought he was done were all
    /// unreachable. The app is the record, and a record that cannot be
    /// corrected is not one — so the session reopens, and finishing it again
    /// keeps the time it was first finished.
    static func actionTitle(for progress: SessionProgress) -> String {
        switch progress {
        case .notStarted: "Start Session"
        case .inProgress: "Resume Session"
        case .finished: "Open Session"
        }
    }

    /// `"Starts tomorrow"`, `"Starts in 3 days"` — how long until a block that
    /// has not begun begins.
    static func start(inDays days: Int) -> String {
        switch days {
        case ..<1: "Starts today"
        case 1: "Starts tomorrow"
        default: "Starts in \(days) days"
        }
    }

    /// `"Tomorrow · Push"`, `"Thursday · Lower"` — the next session the block
    /// prescribes, named by when it falls and what it is for.
    ///
    /// A weekday names itself for anything inside the coming week; past that a
    /// weekday would be ambiguous — "Thursday" could be either of two — so the
    /// count of days is stated instead.
    static func nextLine(
        for day: BlockDay, from now: Date, calendar: Calendar = .current
    ) -> String {
        let when = whenLine(for: day, from: now, calendar: calendar)
        return day.focus.isEmpty ? when : "\(when) · \(day.focus)"
    }

    /// The timing half of `nextLine`, on its own.
    static func whenLine(
        for day: BlockDay, from now: Date, calendar: Calendar = .current
    ) -> String {
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: day.date)
        ).day
        switch days {
        case .some(1): return "Tomorrow"
        case .some(let count) where count >= 7: return "In \(count) days"
        default: return day.weekday.fullName
        }
    }

    /// `"5 exercises"`, and the session's length beside it when the plan stated
    /// one. Nothing is said about a session that prescribes nothing.
    static func sessionShape(exercises: Int, durationMinutes: Int?) -> String? {
        guard exercises > 0 else { return nil }
        let count = "\(exercises) exercise\(exercises == 1 ? "" : "s")"
        guard let durationMinutes else { return count }
        return "\(count) · \(durationMinutes) min"
    }

    /// `"12 of 14 sessions logged"` — what the record holds for a block that is
    /// over. A count of what happened, not a score: nothing here decides
    /// whether it was enough.
    static func recordLine(finished: Int, prescribed: Int) -> String? {
        guard prescribed > 0 else { return nil }
        return "\(finished) of \(prescribed) session\(prescribed == 1 ? "" : "s") logged"
    }

    /// `"Sunday, 16 August"` — the day the screen is talking about.
    ///
    /// The screen was titled "Today" and never said which day that was, so
    /// "Rest day" and "Tomorrow · Push" had nothing to anchor to: a word like
    /// *tomorrow* only means something once *today* has been stated. The
    /// weekday leads because training is scheduled by weekday — "Sunday" is the
    /// part a lifter checks against what the block prescribes.
    static func todayLine(_ now: Date, locale: Locale = .autoupdatingCurrent) -> String {
        now.formatted(
            .dateTime.weekday(.wide).day().month(.wide).locale(locale)
        )
    }
}
