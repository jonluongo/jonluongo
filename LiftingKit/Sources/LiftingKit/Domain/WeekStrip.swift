import Foundation

/// The seven days a week strip shows, and how to step between them.
///
/// **What it does.** Answers the two calendar questions a swipeable week header
/// asks: which seven days sit in the week around the day being shown, and which
/// day a swipe lands on. Both are arithmetic over a calendar, so both live here
/// rather than in a view — a strip that shows the wrong Sunday is a bug a
/// screenshot hides and an assertion does not.
///
/// **How it is used.** Built with the lifter's calendar. `week(containing:)`
/// gives the row of days to draw, and `day(_:steppedBy:within:)` gives the day a
/// left or right swipe moves to — or `nil` at the ends of the range, which is
/// how the caller knows a swipe had nowhere to go.
///
/// **What it depends on.** Foundation's `Calendar`, and nothing else. No store,
/// no view, no notion of a training block: what a given day *prescribes* is
/// `BlockCalendar`'s question, not this one's.
///
/// ## Which seven days
///
/// The week is the lifter's calendar week — it begins on `Calendar.firstWeekday`,
/// so a strip reads `S M T W T F S` where the locale starts weeks on Sunday and
/// `M T W T F S S` where it starts them on Monday. This is deliberately *not*
/// the block's own seven-day week, which `BlockCalendar` counts from the start
/// date: the strip is a calendar, and a calendar whose columns drifted with each
/// block would be unreadable. The two coexist — the strip says which Wednesday,
/// the block says which week of training it falls in.
public struct WeekStrip: Sendable {

    /// The calendar the days are placed in — its time zone decides when a day
    /// rolls, and its `firstWeekday` decides which column a day sits in. The app
    /// passes the lifter's; tests pass a fixed one.
    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// The seven days of the calendar week `date` falls in, earliest first, each
    /// the start of its day.
    ///
    /// A day the calendar cannot produce a date for is left out rather than
    /// given a substitute, so a caller drawing this should draw the days it gets
    /// rather than assume seven. In every ordinary calendar it is seven.
    public func week(containing date: Date) -> [Date] {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        guard let first = calendar.date(byAdding: .day, value: -offset, to: day) else {
            return [day]
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    /// The day `days` steps from `date`, or `nil` when that lands outside
    /// `range`.
    ///
    /// Stepping is by calendar day rather than by 86,400 seconds, so a swipe
    /// across a daylight-saving boundary moves one day rather than landing on
    /// the same day at 23:00. Nothing is clamped: a swipe that would leave the
    /// range answers `nil`, because moving one day less than asked would put the
    /// lifter somewhere he did not choose.
    public func day(
        _ date: Date, steppedBy days: Int, within range: ClosedRange<Date>
    ) -> Date? {
        guard let moved = calendar.date(
            byAdding: .day, value: days, to: calendar.startOfDay(for: date)
        ) else { return nil }
        let first = calendar.startOfDay(for: range.lowerBound)
        let last = calendar.startOfDay(for: range.upperBound)
        guard moved >= first, moved <= last else { return nil }
        return moved
    }
}
