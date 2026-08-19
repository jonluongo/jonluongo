import Foundation

/// What today is, inside a training block.
///
/// **What it does.** Answers the question the app could not previously answer
/// at all: which week the lifter is in, whether today prescribes a session,
/// where that session stands, and what is next. It reports and never advises —
/// "Wednesday, week 2, a rest day, next session Thursday" is a fact about a
/// calendar and a stored plan, and what the lifter should do about it is not
/// this type's business.
///
/// **How it is used.** `RoutineCalendar` produces one; the front door switches on
/// `standing` to choose its screen and reads `upcoming` to say what follows.
/// Both are answered together because a rest day and a session already finished
/// ask the same question — what is next — and neither should have to ask twice.
///
/// **What it depends on.** `BlockDay` and `WeekPlacement`, which are values;
/// nothing persistent, and no view.
public struct TodayInRoutine: Hashable, Sendable {

    /// Where today falls in relation to the block.
    public let standing: Standing

    /// The next session the block prescribes that falls after today and has not
    /// been finished, or `nil` when none remains. Never a session in the past:
    /// a missed day stays missed, and pointing backwards at it would be the app
    /// deciding what should be trained.
    public let upcoming: BlockDay?

    public init(standing: Standing, upcoming: BlockDay?) {
        self.standing = standing
        self.upcoming = upcoming
    }
}

extension TodayInRoutine {

    /// The states today can be in, one per screen the front door draws.
    public enum Standing: Hashable, Sendable {

        /// Nothing dates this block against today: it states no start date, or
        /// the calendar could not count the days between that date and now.
        /// Absence, not an error, and never quietly today.
        case undated

        /// The block states a start date but prescribes no weeks, so there is
        /// nothing to place today against.
        case unscheduled

        /// Today falls before the block's first day.
        case beforeBlock(daysUntilStart: Int)

        /// Today prescribes a session. `BlockDay.progress` says whether it is
        /// untouched, under way, or already finished — all three are still
        /// today's session.
        case session(BlockDay)

        /// Today falls inside the block and prescribes nothing. Roughly two
        /// days in five are this, so it is a state with something to say, not
        /// an empty screen.
        case rest(WeekPlacement)

        /// The record states the block stopped being current on this date. It
        /// does not distinguish a block the lifter finished from one a later
        /// block superseded, and neither does this case — the app does not
        /// invent a difference the record never stored.
        case closed(on: Date)

        /// Every week of the block has elapsed and the record states no closing
        /// date. `endedOn` is the last day the block covered.
        case elapsed(endedOn: Date)

        /// Today's session, when today prescribes one.
        public var session: BlockDay? {
            if case .session(let day) = self { return day }
            return nil
        }

        /// The week today falls in, when today is a rest day inside the block.
        public var rest: WeekPlacement? {
            if case .rest(let week) = self { return week }
            return nil
        }
    }
}

/// Where a week sits in a block, and what the plan called it.
///
/// **What it does.** Carries what a header needs — *"Week 2 of 4 ·
/// Accumulation"* — including the case the store cannot express: an ordinal the
/// block prescribes no week for.
///
/// **How it is used.** Read by the front door's header and by the block view.
/// **What it depends on.** Nothing but Foundation.
public struct WeekPlacement: Hashable, Sendable {

    /// 1-based position of the week today falls in.
    public let ordinal: Int

    /// How many weeks the block covers — its highest stated ordinal, which is
    /// what defines the block's extent even when an ordinal in between is
    /// missing.
    public let totalWeeks: Int

    /// What the block stated at this ordinal. `nil` when it stated no week
    /// there at all, which is a gap the plan left and not a week it named
    /// nothing.
    public let stated: StatedWeek?

    public init(ordinal: Int, totalWeeks: Int, stated: StatedWeek?) {
        self.ordinal = ordinal
        self.totalWeeks = totalWeeks
        self.stated = stated
    }

    /// What a plan said about a week, as opposed to where the week sits.
    public struct StatedWeek: Hashable, Sendable {
        /// Empty when the plan named the week nothing.
        public let label: String
        public let isDeload: Bool

        public init(label: String, isDeload: Bool) {
            self.label = label
            self.isDeload = isDeload
        }
    }
}

/// One prescribed session, placed on a date.
///
/// **What it does.** Joins a `ScheduledDay` to the calendar day it falls on and
/// to the week it belongs to, which is everything a screen needs to name a
/// session and everything a caller needs to find its own stored row again.
///
/// **How it is used.** Returned as today's session and as what is next. The app
/// looks its `WorkoutDay` back up by `week.ordinal` and `weekday`, so nothing
/// persistent has to travel through pure code.
///
/// **What it depends on.** `WeekPlacement`, `Weekday`, `SessionProgress`.
public struct BlockDay: Hashable, Sendable {

    public let week: WeekPlacement
    public let weekday: Weekday
    /// Short label such as `"Push"`. Empty when the plan named none.
    public let focus: String
    /// The start of the calendar day this session falls on, in the calendar the
    /// answer was derived with.
    public let date: Date
    public let progress: SessionProgress

    public init(
        week: WeekPlacement, weekday: Weekday, focus: String,
        date: Date, progress: SessionProgress
    ) {
        self.week = week
        self.weekday = weekday
        self.focus = focus
        self.date = date
        self.progress = progress
    }
}
