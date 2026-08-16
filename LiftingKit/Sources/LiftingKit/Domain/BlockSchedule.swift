import Foundation

/// A training block reduced to the only things a calendar question needs: when
/// it started, whether the record has closed it, and which sessions each week
/// prescribes.
///
/// **What it does.** Carries a block's shape as plain values, so "what is
/// today?" can be answered without a database, a simulator, or a model. It
/// states absence honestly: `startDate` is optional because a block nobody
/// dated cannot be placed on a calendar, and answering "today" for it would be
/// inventing the one fact that was missing.
///
/// **How it is used.** The app builds one from its stored `TrainingPlan` and
/// hands it to `BlockCalendar`. It is a snapshot, not a store: nothing here is
/// written back, and the answer refers to weeks and weekdays rather than to
/// records, so the caller looks its own rows back up by position.
///
/// **What it depends on.** `Weekday`, and Foundation's `Date`. Nothing else.
public struct BlockSchedule: Hashable, Sendable {

    /// When the block's first week begins. `nil` when the block states no
    /// start date — absence, never today.
    public let startDate: Date?

    /// When the record says this block stopped being the current one. Note this
    /// date is written both when a lifter finishes a block and when a later
    /// block supersedes it; the two are not distinguished in the record, so
    /// nothing here distinguishes them either.
    public let closedAt: Date?

    /// The weeks the block prescribes, in whatever order they were handed over.
    /// Ordinals decide position, not array order, and a missing ordinal is a
    /// gap the plan left rather than a week to be closed up.
    public let weeks: [ScheduledWeek]

    public init(startDate: Date?, closedAt: Date? = nil, weeks: [ScheduledWeek]) {
        self.startDate = startDate
        self.closedAt = closedAt
        self.weeks = weeks
    }
}

/// One week of a block, as a value: where it sits, what the plan called it, and
/// which days it trains.
///
/// **What it does.** States a week's position and its sessions without the
/// store. **How it is used.** Assembled into a `BlockSchedule`.
/// **What it depends on.** `ScheduledDay`.
public struct ScheduledWeek: Hashable, Sendable {

    /// 1-based position within the block, exactly as the plan stated it.
    public let ordinal: Int
    /// What the plan called this week — `"Accumulation"`, `"Deload"`. Empty
    /// when the plan named none.
    public let label: String
    public let isDeload: Bool
    /// The sessions this week prescribes, at most one per weekday. Empty for a
    /// week whose sessions have not arrived.
    public let days: [ScheduledDay]

    public init(
        ordinal: Int, label: String = "", isDeload: Bool = false, days: [ScheduledDay]
    ) {
        self.ordinal = ordinal
        self.label = label
        self.isDeload = isDeload
        self.days = days
    }
}

/// One prescribed session within a week, as a value.
///
/// **What it does.** Names the weekday the session falls on, what it is for,
/// and how far the lifter has got with it. **How it is used.** Assembled into a
/// `ScheduledWeek`; `BlockCalendar` gives it a date.
/// **What it depends on.** `Weekday` and `SessionProgress`.
public struct ScheduledDay: Hashable, Sendable {

    public let weekday: Weekday
    /// Short label such as `"Push"`. Empty when the plan named none.
    public let focus: String
    public let progress: SessionProgress

    public init(weekday: Weekday, focus: String = "", progress: SessionProgress = .notStarted) {
        self.weekday = weekday
        self.focus = focus
        self.progress = progress
    }
}

/// How far a lifter has got with one prescribed session.
///
/// **What it does.** Gives the front door the one thing that decides between
/// "Start" and "Resume", as a single value rather than a pair of booleans that
/// could say both.
///
/// **How it is used.** The app reads it off its stored session. A session is
/// `.finished` when the record carries the date it was finished on, and
/// `.inProgress` when it is not finished and at least one set has been ticked.
/// A ticked set is the earliest evidence of real work, because opening the
/// logging screen already writes an empty row for every set the plan
/// prescribed — rows exist because the screen was opened, not because anything
/// was lifted.
///
/// **What it depends on.** Foundation's `Date`.
public enum SessionProgress: Hashable, Sendable {

    /// Nothing has been logged against this session.
    case notStarted
    /// Some work is logged and the session has not been finished.
    case inProgress
    /// The lifter finished the session, on this date.
    case finished(Date)

    public var isFinished: Bool {
        if case .finished = self { return true }
        return false
    }
}
