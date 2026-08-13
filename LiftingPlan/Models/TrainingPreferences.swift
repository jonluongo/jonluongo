import Foundation
import SwiftData

/// The user's standing setup: when they train, how long, their goal, and context.
/// A single instance is kept in the store and edited from Setup / Settings.
@Model
final class TrainingPreferences {
    /// Stored as raw `Weekday` values so SwiftData can persist it simply.
    var weekdayRawValues: [Int]
    var durationMinutes: Int
    var goal: String
    private var equipmentRaw: String
    private var experienceRaw: String
    /// Set once the user has completed initial setup at least once.
    var hasCompletedSetup: Bool
    var updatedAt: Date

    init(
        weekdays: Set<Weekday> = [.monday, .wednesday, .friday],
        durationMinutes: Int = 45,
        goal: String = "",
        equipment: Equipment = .fullGym,
        experience: ExperienceLevel = .intermediate,
        hasCompletedSetup: Bool = false
    ) {
        self.weekdayRawValues = weekdays.map(\.rawValue).sorted()
        self.durationMinutes = durationMinutes
        self.goal = goal
        self.equipmentRaw = equipment.rawValue
        self.experienceRaw = experience.rawValue
        self.hasCompletedSetup = hasCompletedSetup
        self.updatedAt = Date()
    }

    var weekdays: Set<Weekday> {
        get { Set(weekdayRawValues.compactMap(Weekday.init(rawValue:))) }
        set { weekdayRawValues = newValue.map(\.rawValue).sorted() }
    }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .fullGym }
        set { equipmentRaw = newValue.rawValue }
    }

    var experience: ExperienceLevel {
        get { ExperienceLevel(rawValue: experienceRaw) ?? .intermediate }
        set { experienceRaw = newValue.rawValue }
    }

    /// Weekdays in Monday-first display order.
    var orderedWeekdays: [Weekday] {
        Weekday.displayOrder.filter { weekdays.contains($0) }
    }
}
