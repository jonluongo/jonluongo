import Foundation
import SwiftData
import LiftingKit

/// One training day within a week.
///
/// Read `orderedExercises` rather than `exercises` — SwiftData does not
/// guarantee relationship ordering, and compounds-first order matters.
///
/// Every property has a default, as CloudKit requires. Depends on: `Weekday`.
@Model
final class WorkoutDay {
    var weekdayRawValue: Int = Weekday.monday.rawValue
    /// Short label such as "Push" or "Lower Body".
    var focus: String = ""
    /// How long this session runs. `nil` when the plan did not say.
    var durationMinutes: Int?
    var completedAt: Date?

    var week: TrainingWeek?

    @Relationship(deleteRule: .cascade, inverse: \PlannedExercise.day)
    var exercises: [PlannedExercise]? = []

    init(
        weekday: Weekday = .monday, focus: String = "",
        durationMinutes: Int? = nil, completedAt: Date? = nil
    ) {
        self.weekdayRawValue = weekday.rawValue
        self.focus = focus
        self.durationMinutes = durationMinutes
        self.completedAt = completedAt
    }

    var weekday: Weekday {
        get { Weekday(rawValue: weekdayRawValue) ?? .monday }
        set { weekdayRawValue = newValue.rawValue }
    }

    /// Exercises in prescribed order — compounds first.
    var orderedExercises: [PlannedExercise] {
        (exercises ?? []).sorted { $0.order < $1.order }
    }

    /// When training began: the earliest set of this session that was ticked,
    /// or `nil` while none has been.
    ///
    /// The logging screen's clock used to count from the moment the screen
    /// opened, which meant it restarted every time the session was closed and
    /// resumed — it was timing the sheet, not the workout. This is a fact the
    /// record already holds, so it survives closing, backgrounding, relaunching
    /// and syncing without anything new being stored.
    ///
    /// A ticked set is the anchor because it is the earliest point at which the
    /// lifter is demonstrably training — the same evidence `TodayInPlan` already
    /// uses to tell a session in progress from one merely opened. Warm-ups
    /// count: he is in the gym. Before the first tick there is no elapsed time
    /// to report, and reporting one would be timing how long he looked at a
    /// screen.
    var startedAt: Date? {
        (exercises ?? [])
            .flatMap { $0.loggedSets ?? [] }
            .filter(\.isCompleted)
            .map(\.completedAt)
            .min()
    }

    /// When the last set of this session was ticked, or `nil` while none has
    /// been.
    ///
    /// The other end of `startedAt`, and the reason the clock does not run
    /// overnight. A session left open — the lifter ticked a set, went home, came
    /// back the next evening — was reporting the hours since he started rather
    /// than the hour he trained; it read `1429:59`. Between the first tick and
    /// the last is the span the record can actually vouch for. It advances as
    /// sets are ticked and stops when he stops.
    var lastLoggedAt: Date? {
        (exercises ?? [])
            .flatMap { $0.loggedSets ?? [] }
            .filter(\.isCompleted)
            .map(\.completedAt)
            .max()
    }

    /// How many rows of this session have not been ticked.
    ///
    /// Rows exist from the moment the screen is opened — one per prescribed set
    /// — so this counts what the plan asked for and the lifter has not yet
    /// marked as done. It decides nothing: finishing a session with sets left is
    /// entirely allowed, and often correct. It is only what the screen uses to
    /// say so before it happens.
    var unloggedSetCount: Int {
        (exercises ?? [])
            .flatMap { $0.loggedSets ?? [] }
            .count { !$0.isCompleted }
    }
}
