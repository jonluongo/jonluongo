import Foundation
import SwiftData

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
    var durationMinutes: Int = 45
    var completedAt: Date?

    var week: TrainingWeek?

    @Relationship(deleteRule: .cascade, inverse: \PlannedExercise.day)
    var exercises: [PlannedExercise]? = []

    init(
        weekday: Weekday = .monday, focus: String = "",
        durationMinutes: Int = 45, completedAt: Date? = nil
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
}
