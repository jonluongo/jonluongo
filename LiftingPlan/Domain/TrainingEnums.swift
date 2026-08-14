import Foundation

/// Days of the week the user can train on. `rawValue` matches `Calendar`'s
/// 1-based weekday numbering (1 = Sunday) so it maps cleanly to date math.
enum Weekday: Int, CaseIterable, Codable, Identifiable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    var shortName: String {
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

    var fullName: String {
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
    static var displayOrder: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What equipment the lifter has access to. Shapes the exercises the model picks.
enum Equipment: String, CaseIterable, Codable, Identifiable {
    case fullGym = "Full gym"
    case dumbbellsOnly = "Dumbbells only"
    case homeMinimal = "Home / minimal"
    case bodyweight = "Bodyweight only"

    var id: String { rawValue }

    var promptDescription: String {
        switch self {
        case .fullGym: "a fully equipped commercial gym (barbells, machines, cables, dumbbells)"
        case .dumbbellsOnly: "an adjustable set of dumbbells and a bench"
        case .homeMinimal: "a minimal home setup (some dumbbells, resistance bands, a pull-up bar)"
        case .bodyweight: "no equipment — bodyweight movements only"
        }
    }
}

/// Rough training age. Used to set volume, complexity, and how hard to push.
enum ExperienceLevel: String, CaseIterable, Codable, Identifiable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"

    var id: String { rawValue }

    var promptDescription: String {
        switch self {
        case .beginner: "new to lifting (less than a year of consistent training)"
        case .intermediate: "1–3 years of consistent training"
        case .advanced: "3+ years of consistent, structured training"
        }
    }
}
