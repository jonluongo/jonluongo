import Foundation

/// Days of the week the user can train on. `rawValue` matches `Calendar`'s
/// 1-based weekday numbering (1 = Sunday) so it maps cleanly to date math.
public enum Weekday: Int, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    public var id: Int { rawValue }

    public var shortName: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }

    public var fullName: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }

    /// Monday-first ordering for display (most lifters think of the week that way).
    public static var displayOrder: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A coarse description of a gym, offered as shorthand for the equipment such a
/// gym usually holds.
///
/// **It is never what is stored.** What a lifter owns is an open set of
/// `EquipmentType`, because a real gym is not a tier: "barbell and bands but no
/// rack" is none of these, and forcing it into the nearest one either grants him
/// machines he does not have or denies him the bar he does. Use a tier only to
/// say several types at once — `EquipmentAccess.permitted(for:)` expands one
/// into the types it stands for — and expect the expansion, not the tier, to be
/// what is recorded and what anything filters on.
///
/// Because it is never stored, a description this list does not have can never
/// reject a document; it is simply not one of the shorthands on offer.
public enum Equipment: String, CaseIterable, Codable, Sendable, Identifiable {
    case fullGym = "Full gym"
    case dumbbellsOnly = "Dumbbells only"
    case homeMinimal = "Home / minimal"
    case bodyweight = "Bodyweight only"

    public var id: String { rawValue }
}

/// Rough training age, as the lifter describes it. Recorded, not acted on.
public enum ExperienceLevel: String, CaseIterable, Codable, Sendable, Identifiable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"

    public var id: String { rawValue }
}
