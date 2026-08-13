import Foundation
import SwiftData

/// A single training day within a plan (e.g. "Push", "Lower Body").
@Model
final class WorkoutSession {
    private var weekdayRaw: Int
    /// Short focus label, e.g. "Push", "Pull", "Legs", "Full Body".
    var focus: String
    var targetDurationMinutes: Int
    /// Position within the week, used for stable ordering.
    var order: Int
    var completedAt: Date?

    var plan: WorkoutPlan?

    @Relationship(deleteRule: .cascade, inverse: \PlannedExercise.session)
    var exercises: [PlannedExercise]

    init(
        weekday: Weekday,
        focus: String,
        targetDurationMinutes: Int,
        order: Int,
        exercises: [PlannedExercise] = []
    ) {
        self.weekdayRaw = weekday.rawValue
        self.focus = focus
        self.targetDurationMinutes = targetDurationMinutes
        self.order = order
        self.exercises = exercises
    }

    var weekday: Weekday {
        get { Weekday(rawValue: weekdayRaw) ?? .monday }
        set { weekdayRaw = newValue.rawValue }
    }

    var orderedExercises: [PlannedExercise] {
        exercises.sorted { $0.order < $1.order }
    }

    var isCompleted: Bool { completedAt != nil }

    /// True once every planned exercise has at least its target number of sets logged.
    var allExercisesLogged: Bool {
        !exercises.isEmpty && exercises.allSatisfy { $0.isComplete }
    }

    var title: String { "\(weekday.fullName) · \(focus)" }
}
