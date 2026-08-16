import Foundation

/// Places a date inside a training block: which week, which day, whether today
/// trains, and what is next.
///
/// **What it does.** Answers the question the app had no way to answer, which
/// is why every week of a block used to render identically. It reports and
/// never advises: where today falls is arithmetic over a start date and stored
/// ordinals, and what the lifter should do about it is not decided here.
///
/// **How it is used.** Build one with the lifter's calendar, hand it a
/// `BlockSchedule` and the current date, and switch on the `TodayInBlock` it
/// returns. Both the calendar and "now" are arguments rather than globals,
/// which is what lets the whole derivation be tested without a simulator, a
/// database, or a particular machine's time zone.
///
/// **What it depends on.** Foundation's `Calendar`, and the value types in
/// `BlockSchedule`. Nothing persistent, nothing visual.
///
/// ## How a date is anchored
///
/// **A week is seven days from the block's start date, not a calendar week.**
/// Week 1 covers the start date and the six days after it, week 2 the seven
/// after that, and so on. Within a week, a session's weekday names its offset
/// from the week's first day.
///
/// This is a stated assumption, and it is the one that loses nothing. Anchoring
/// instead to the calendar week containing the start date would put part of
/// week 1 before the block began — a Monday session on a block imported on
/// Wednesday would be in the past on arrival, unreachable and never trained.
/// It would also depend on `Calendar.firstWeekday`, a locale setting, so the
/// same plan would mean different dates for two lifters in different regions.
/// Seven days from the start date has neither problem: every session the plan
/// prescribes gets exactly one date, and consecutive weeks are exactly seven
/// days apart.
///
/// ## Which day it is
///
/// Days are keyed by `calendar.startOfDay(for:)` on both sides, so the day
/// rolls at the lifter's own midnight, in the time zone their calendar carries.
/// 23:00 on Wednesday is Wednesday and 01:00 on Thursday is Thursday, even
/// though both instants are the same UTC day — which is the answer that does
/// not surprise anyone standing in a gym. Because both ends of the count are
/// midnights and the arithmetic goes through the calendar rather than through
/// seconds, a week that gains or loses an hour to daylight saving is still
/// seven days.
public struct BlockCalendar: Sendable {

    /// The calendar the answer is derived in — crucially, the time zone it
    /// carries. The app passes `.current`; tests pass a fixed one.
    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Where `now` falls in `schedule`, and what the block prescribes next.
    public func today(in schedule: BlockSchedule, on now: Date) -> TodayInBlock {
        // A closed block is over regardless of what its weeks would cover. The
        // record does not say whether it was finished or superseded, so neither
        // does this.
        if let closedAt = schedule.closedAt {
            return TodayInBlock(standing: .closed(on: closedAt), upcoming: nil)
        }
        guard let startDate = schedule.startDate else {
            return TodayInBlock(standing: .undated, upcoming: nil)
        }
        guard let totalWeeks = schedule.weeks.map(\.ordinal).max() else {
            return TodayInBlock(standing: .unscheduled, upcoming: nil)
        }

        let blockStart = calendar.startOfDay(for: startDate)
        let todayStart = calendar.startOfDay(for: now)
        guard
            let elapsedDays = calendar.dateComponents(
                [.day], from: blockStart, to: todayStart
            ).day
        else {
            return TodayInBlock(standing: .undated, upcoming: nil)
        }

        let dated = datedDays(in: schedule, from: blockStart, totalWeeks: totalWeeks)
        let upcoming = dated.first { $0.date > todayStart && !$0.progress.isFinished }

        if elapsedDays < 0 {
            return TodayInBlock(
                standing: .beforeBlock(daysUntilStart: -elapsedDays), upcoming: upcoming)
        }

        let ordinal = elapsedDays / 7 + 1
        if ordinal > totalWeeks {
            guard let endedOn = calendar.date(
                byAdding: .day, value: totalWeeks * 7 - 1, to: blockStart
            ) else {
                return TodayInBlock(standing: .undated, upcoming: nil)
            }
            return TodayInBlock(standing: .elapsed(endedOn: endedOn), upcoming: upcoming)
        }

        let placement = self.placement(of: ordinal, in: schedule, totalWeeks: totalWeeks)
        if let session = dated.first(where: { $0.date == todayStart }) {
            return TodayInBlock(standing: .session(session), upcoming: upcoming)
        }
        return TodayInBlock(standing: .rest(placement), upcoming: upcoming)
    }

    // MARK: - Placing weeks and days

    /// Where an ordinal sits and what, if anything, the block stated there. An
    /// ordinal the block skipped is stated as `nil` rather than as a week
    /// nobody named, because a gap and an unnamed week are different facts.
    private func placement(
        of ordinal: Int, in schedule: BlockSchedule, totalWeeks: Int
    ) -> WeekPlacement {
        let stated = schedule.weeks.first { $0.ordinal == ordinal }
        return WeekPlacement(
            ordinal: ordinal,
            totalWeeks: totalWeeks,
            stated: stated.map {
                WeekPlacement.StatedWeek(label: $0.label, isDeload: $0.isDeload)
            }
        )
    }

    /// Every session the block prescribes, each on the date it falls, earliest
    /// first.
    ///
    /// A session in week `n` on weekday `w` falls `(w - startWeekday) mod 7`
    /// days after that week's first day, which is `7 * (n - 1)` days after the
    /// block's. A day the calendar cannot produce a date for is left out rather
    /// than given a substitute date.
    private func datedDays(
        in schedule: BlockSchedule, from blockStart: Date, totalWeeks: Int
    ) -> [BlockDay] {
        let startWeekday = calendar.component(.weekday, from: blockStart)
        return schedule.weeks.flatMap { week -> [BlockDay] in
            let placement = placement(of: week.ordinal, in: schedule, totalWeeks: totalWeeks)
            return week.days.compactMap { day -> BlockDay? in
                let offset = (day.weekday.rawValue - startWeekday + 7) % 7
                guard let date = calendar.date(
                    byAdding: .day, value: (week.ordinal - 1) * 7 + offset, to: blockStart
                ) else { return nil }
                return BlockDay(
                    week: placement, weekday: day.weekday, focus: day.focus,
                    date: date, progress: day.progress
                )
            }
        }
        .sorted { $0.date < $1.date }
    }
}
