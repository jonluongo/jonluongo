import Foundation
import SwiftData
import LiftingKit

/// A training block: a fixed-length program the lifter is working through.
///
/// This is the top of the user-data hierarchy and the unit the interface
/// treats as a project — it owns its weeks. A plan is finite by design, so
/// finishing one is a real event a future block can respond to.
///
/// Every property has a default, as CloudKit requires.
/// Depends on: `Weekday`.
@Model
final class TrainingPlan {
    var title: String = ""
    var goal: String = ""
    var startDate: Date = Date()
    /// How many weeks the block runs. `nil` until a plan says.
    var weekCount: Int?
    var completedAt: Date?
    /// The `ExerciseCatalog.version` that produced this plan's exercise
    /// selections. A later correction to the catalog (e.g. reclassifying an
    /// exercise's muscles) can change what an already-logged set means; this
    /// stamp is what lets a future release detect a plan built against older
    /// catalog data rather than silently reinterpreting it.
    var catalogVersion: Int = 1
    /// Which days this block trains. Different blocks may train different days.
    /// Empty until a plan says which.
    private var weekdayRawValues: [Int] = []
    /// How long a session in this block runs. `nil` until a plan says.
    var durationMinutes: Int?

    @Relationship(deleteRule: .cascade, inverse: \TrainingWeek.plan)
    var weeks: [TrainingWeek]? = []

    init(
        title: String = "", goal: String = "", startDate: Date = Date(),
        weekCount: Int? = nil, weekdays: Set<Weekday> = [],
        durationMinutes: Int? = nil, catalogVersion: Int = 1
    ) {
        self.title = title
        self.goal = goal
        self.startDate = startDate
        self.weekCount = weekCount
        self.weekdayRawValues = weekdays.map(\.rawValue).sorted()
        self.durationMinutes = durationMinutes
        self.catalogVersion = catalogVersion
    }

    var weekdays: Set<Weekday> {
        get { Set(weekdayRawValues.compactMap(Weekday.init(rawValue:))) }
        set { weekdayRawValues = newValue.map(\.rawValue).sorted() }
    }

    /// Training days in Monday-first display order.
    var orderedWeekdays: [Weekday] {
        Weekday.displayOrder.filter { weekdays.contains($0) }
    }

    /// Weeks in program order.
    var orderedWeeks: [TrainingWeek] {
        (weeks ?? []).sorted { $0.ordinal < $1.ordinal }
    }

    var isComplete: Bool { completedAt != nil }
}
