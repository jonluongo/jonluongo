import Foundation

/// One training block inside a `TrainingSnapshot`: a finite program with its
/// weeks, days, prescribed exercises, and the sets logged against them.
///
/// Read it to see what was prescribed and what actually happened. Every value
/// is carried exactly as it was prescribed — nothing here caps a set count,
/// fills an empty rep range, or supplies a rest that was never given.
/// `catalogVersion` is the catalog generation this block's exercises were
/// selected from, which may be older than the snapshot's own.
///
/// Depends on: `Weekday`, `SnapshotWeek`.
public struct SnapshotPlan: Codable, Hashable, Sendable {
    public let title: String
    public let goal: String
    public let startDate: Date
    /// How many weeks the block runs. `nil` when the plan did not say.
    public let weekCount: Int?
    /// When the block was finished. `nil` while it is still running.
    public let completedAt: Date?
    /// The catalog generation this block's exercise IDs were selected from.
    public let catalogVersion: Int
    /// The days this block trains, which need not match the lifter's stated
    /// preference. Empty when the plan did not say.
    public let weekdays: [Weekday]
    /// How long a session in this block runs. `nil` when the plan did not say.
    public let durationMinutes: Int?
    /// The block's weeks in program order.
    public let weeks: [SnapshotWeek]

    public init(
        title: String, goal: String, startDate: Date, weekCount: Int?,
        completedAt: Date?, catalogVersion: Int, weekdays: [Weekday],
        durationMinutes: Int?, weeks: [SnapshotWeek]
    ) {
        self.title = title
        self.goal = goal
        self.startDate = startDate
        self.weekCount = weekCount
        self.completedAt = completedAt
        self.catalogVersion = catalogVersion
        self.weekdays = weekdays
        self.durationMinutes = durationMinutes
        self.weeks = weeks
    }
}

/// One week of a block. Weeks are concrete and may differ from one another —
/// a deload prescribes genuinely less work, not the same work lighter.
///
/// Read `days` in the order given; the exporter writes them Monday-first.
/// Depends on: `SnapshotDay`.
public struct SnapshotWeek: Codable, Hashable, Sendable {
    /// 1-based position within the plan.
    public let ordinal: Int
    /// Short label such as "Accumulation". May be empty.
    public let label: String
    public let isDeload: Bool
    public let days: [SnapshotDay]

    public init(ordinal: Int, label: String, isDeload: Bool, days: [SnapshotDay]) {
        self.ordinal = ordinal
        self.label = label
        self.isDeload = isDeload
        self.days = days
    }
}

/// One training day. Read `exercises` in the order given — the exporter writes
/// them in prescribed order, compounds first. Depends on: `Weekday`,
/// `SnapshotPlannedExercise`.
public struct SnapshotDay: Codable, Hashable, Sendable {
    public let weekday: Weekday
    /// Short label such as "Push". May be empty.
    public let focus: String
    /// How long this session runs. `nil` when the plan did not say.
    public let durationMinutes: Int?
    /// When the session was finished. `nil` when it has not been.
    public let completedAt: Date?
    public let exercises: [SnapshotPlannedExercise]

    public init(
        weekday: Weekday, focus: String, durationMinutes: Int?,
        completedAt: Date?, exercises: [SnapshotPlannedExercise]
    ) {
        self.weekday = weekday
        self.focus = focus
        self.durationMinutes = durationMinutes
        self.completedAt = completedAt
        self.exercises = exercises
    }
}

/// One prescribed movement and the sets logged against it.
///
/// `exerciseID` is the identity that matters and the only safe key to join a
/// lift's history on; `displayName` is a copy kept so history stays readable
/// if an exercise is later renamed or dropped from the catalog. Never match on
/// the name. Depends on: `ExerciseID`, `Mass`, `SnapshotLoggedSet`.
public struct SnapshotPlannedExercise: Codable, Hashable, Sendable {
    public let exerciseID: ExerciseID
    /// For display only. Never an identity or a join key.
    public let displayName: String
    /// Position within the day, ascending.
    public let order: Int
    public let targetSets: Int
    /// The rep target as written, e.g. "8-12" or "5". May be empty when none
    /// was prescribed. Parse it with `RepRange` rather than by hand.
    public let repRange: String
    /// The load the plan suggested, in the unit it was written in. `nil` when
    /// none was given.
    public let suggestedLoad: Mass?
    /// Prescribed rest between sets, in seconds. `nil` when none was
    /// prescribed — not zero, which would read as "rest none".
    public let restSeconds: Int?
    /// Rep tempo such as "3-0-1-0". `nil` when none was given.
    public let tempo: String?
    public let notes: String?
    /// Sets logged against this exercise, in logging order. Includes warmups
    /// and incomplete rows; each set says which it is.
    public let loggedSets: [SnapshotLoggedSet]

    public init(
        exerciseID: ExerciseID, displayName: String, order: Int, targetSets: Int,
        repRange: String, suggestedLoad: Mass?, restSeconds: Int?, tempo: String?,
        notes: String?, loggedSets: [SnapshotLoggedSet]
    ) {
        self.exerciseID = exerciseID
        self.displayName = displayName
        self.order = order
        self.targetSets = targetSets
        self.repRange = repRange
        self.suggestedLoad = suggestedLoad
        self.restSeconds = restSeconds
        self.tempo = tempo
        self.notes = notes
        self.loggedSets = loggedSets
    }
}

/// One set as the lifter logged it: what he lifted, for how many, how hard it
/// felt, and when.
///
/// A row exists as soon as it is on screen, so read `isCompleted` rather than
/// existence to know work was done, and `isWarmup` to know whether it counts.
/// `load` is `nil` for a bodyweight movement rather than zero, so "no external
/// weight" and "an empty bar" stay distinguishable. Depends on: `Mass`.
public struct SnapshotLoggedSet: Codable, Hashable, Sendable {
    /// Position within the exercise, ascending.
    public let setIndex: Int
    /// The weight as entered, in the unit entered. `nil` means bodyweight.
    public let load: Mass?
    public let reps: Int
    /// Rating of perceived exertion, 1–10. `nil` when not rated.
    public let rpe: Double?
    public let isCompleted: Bool
    public let isWarmup: Bool
    public let completedAt: Date

    public init(
        setIndex: Int, load: Mass?, reps: Int, rpe: Double?,
        isCompleted: Bool, isWarmup: Bool, completedAt: Date
    ) {
        self.setIndex = setIndex
        self.load = load
        self.reps = reps
        self.rpe = rpe
        self.isCompleted = isCompleted
        self.isWarmup = isWarmup
        self.completedAt = completedAt
    }
}
