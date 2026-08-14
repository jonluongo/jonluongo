import Foundation
import SwiftData

/// One week within a training block.
///
/// Weeks are stored concretely and may differ from one another — that is the
/// whole reason this layer exists. A deload week prescribes genuinely less
/// work than the week before it, rather than the same work at a lower load.
///
/// Every property has a default, as CloudKit requires.
@Model
final class TrainingWeek {
    /// 1-based position within the plan.
    var ordinal: Int = 1
    /// Short label such as "Accumulation" or "Deload". May be empty.
    var label: String = ""
    var isDeload: Bool = false

    var plan: TrainingPlan?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutDay.week)
    var days: [WorkoutDay]? = []

    init(ordinal: Int = 1, label: String = "", isDeload: Bool = false) {
        self.ordinal = ordinal
        self.label = label
        self.isDeload = isDeload
    }

    /// Days in Monday-first display order.
    var orderedDays: [WorkoutDay] {
        (days ?? []).sorted {
            (Weekday.displayOrder.firstIndex(of: $0.weekday) ?? 0)
                < (Weekday.displayOrder.firstIndex(of: $1.weekday) ?? 0)
        }
    }
}
