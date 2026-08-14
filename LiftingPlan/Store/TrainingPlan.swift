import Foundation
import SwiftData

/// A training block: a fixed-length program the lifter is working through.
///
/// This is the top of the user-data hierarchy and the unit the interface
/// treats as a project — it owns its weeks and its conversation. A plan is
/// finite by design, so finishing one is a real event the chat can respond to
/// by proposing the next block.
///
/// Every property has a default, as CloudKit requires.
/// Depends on: `Weekday`.
@Model
final class TrainingPlan {
    var title: String = ""
    var goal: String = ""
    var startDate: Date = Date()
    /// How many weeks the block runs. Typically 8–12.
    var weekCount: Int = 8
    var completedAt: Date?
    /// Whether the on-device model produced this plan or the template did.
    var wasModelGenerated: Bool = false
    /// Which days this block trains. Different blocks may train different days.
    private var weekdayRawValues: [Int] = [
        Weekday.monday.rawValue, Weekday.wednesday.rawValue, Weekday.friday.rawValue,
    ]
    var durationMinutes: Int = 45

    @Relationship(deleteRule: .cascade, inverse: \TrainingWeek.plan)
    var weeks: [TrainingWeek]? = []

    @Relationship(deleteRule: .cascade, inverse: \PlanMessage.plan)
    var messages: [PlanMessage]? = []

    init(
        title: String = "", goal: String = "", startDate: Date = Date(),
        weekCount: Int = 8, weekdays: Set<Weekday> = [.monday, .wednesday, .friday],
        durationMinutes: Int = 45, wasModelGenerated: Bool = false
    ) {
        self.title = title
        self.goal = goal
        self.startDate = startDate
        self.weekCount = weekCount
        self.weekdayRawValues = weekdays.map(\.rawValue).sorted()
        self.durationMinutes = durationMinutes
        self.wasModelGenerated = wasModelGenerated
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

    /// Conversation in chronological order.
    var orderedMessages: [PlanMessage] {
        (messages ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var isComplete: Bool { completedAt != nil }
}
