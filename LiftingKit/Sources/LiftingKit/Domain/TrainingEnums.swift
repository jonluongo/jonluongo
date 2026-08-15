import Foundation

/// Days of the week the user can train on. `rawValue` matches `Calendar`'s
/// 1-based weekday numbering (1 = Sunday) so it maps cleanly to date math.
public enum Weekday: Int, CaseIterable, Codable, Identifiable, Comparable {
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

/// What equipment the lifter has access to — a fact about his gym, which
/// `EquipmentAccess` turns into the concrete `EquipmentType`s it grants.
public enum Equipment: String, CaseIterable, Codable, Identifiable {
    case fullGym = "Full gym"
    case dumbbellsOnly = "Dumbbells only"
    case homeMinimal = "Home / minimal"
    case bodyweight = "Bodyweight only"

    public var id: String { rawValue }
}

/// Rough training age, as the lifter describes it. Recorded, not acted on.
public enum ExperienceLevel: String, CaseIterable, Codable, Identifiable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"

    public var id: String { rawValue }
}
