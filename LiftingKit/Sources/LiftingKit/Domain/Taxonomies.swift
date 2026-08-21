import Foundation

/// A muscle targeted by an exercise, as named by the bundled catalog.
///
/// Use `primary` and `secondary` collections on `Exercise` rather than
/// constructing these directly. Depends on: `ExtensibleTaxonomy`.
public struct MuscleGroup: ExtensibleTaxonomy {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = Self.canonicalized(rawValue) }

    public static let abdominals = MuscleGroup(rawValue: "abdominals")
    public static let abductors = MuscleGroup(rawValue: "abductors")
    public static let adductors = MuscleGroup(rawValue: "adductors")
    public static let biceps = MuscleGroup(rawValue: "biceps")
    public static let calves = MuscleGroup(rawValue: "calves")
    public static let chest = MuscleGroup(rawValue: "chest")
    public static let forearms = MuscleGroup(rawValue: "forearms")
    public static let glutes = MuscleGroup(rawValue: "glutes")
    public static let hamstrings = MuscleGroup(rawValue: "hamstrings")
    public static let lats = MuscleGroup(rawValue: "lats")
    public static let lowerBack = MuscleGroup(rawValue: "lower back")
    public static let middleBack = MuscleGroup(rawValue: "middle back")
    public static let neck = MuscleGroup(rawValue: "neck")
    public static let quadriceps = MuscleGroup(rawValue: "quadriceps")
    public static let shoulders = MuscleGroup(rawValue: "shoulders")
    public static let traps = MuscleGroup(rawValue: "traps")
    public static let triceps = MuscleGroup(rawValue: "triceps")

    public static let known: [MuscleGroup] = [
        .abdominals, .abductors, .adductors, .biceps, .calves, .chest,
        .forearms, .glutes, .hamstrings, .lats, .lowerBack, .middleBack,
        .neck, .quadriceps, .shoulders, .traps, .triceps,
    ]
}

/// What the lifter needs to hand to perform an exercise.
///
/// Read it from an `Exercise`, or filter the catalog by it through
/// `ExerciseFilter`. Depends on: `ExtensibleTaxonomy`.
public struct EquipmentType: ExtensibleTaxonomy {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = Self.canonicalized(rawValue) }

    public static let bodyweight = EquipmentType(rawValue: "bodyweight")
    public static let barbell = EquipmentType(rawValue: "barbell")
    public static let dumbbell = EquipmentType(rawValue: "dumbbell")
    public static let kettlebell = EquipmentType(rawValue: "kettlebell")
    public static let cable = EquipmentType(rawValue: "cable")
    public static let machine = EquipmentType(rawValue: "machine")
    public static let band = EquipmentType(rawValue: "band")
    public static let ezBar = EquipmentType(rawValue: "ez bar")
    public static let trapBar = EquipmentType(rawValue: "trap bar")
    public static let medicineBall = EquipmentType(rawValue: "medicine ball")
    public static let plate = EquipmentType(rawValue: "plate")
    public static let suspension = EquipmentType(rawValue: "suspension")
    public static let sled = EquipmentType(rawValue: "sled")
    public static let cardioMachine = EquipmentType(rawValue: "cardio machine")
    /// A swimming pool. What the lifter has access to is prose in `user.md`,
    /// so nothing here has to guess whether "full gym" means there is a pool in
    /// the building.
    public static let pool = EquipmentType(rawValue: "pool")
    public static let other = EquipmentType(rawValue: "other")

    public static let known: [EquipmentType] = [
        .bodyweight, .barbell, .dumbbell, .kettlebell, .cable, .machine,
        .band, .ezBar, .trapBar, .medicineBall, .plate, .suspension,
        .sled, .cardioMachine, .pool, .other,
    ]
}

/// The movement pattern an exercise trains.
///
/// It is what makes two exercises comparable — `ExerciseCatalog.substitutes`
/// searches within a pattern, and a lifter's avoided patterns are recorded
/// against it. Depends on: `ExtensibleTaxonomy`.
public struct MovementPattern: ExtensibleTaxonomy {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = Self.canonicalized(rawValue) }

    public static let squat = MovementPattern(rawValue: "squat")
    public static let hinge = MovementPattern(rawValue: "hinge")
    public static let lunge = MovementPattern(rawValue: "lunge")
    public static let horizontalPress = MovementPattern(rawValue: "horizontal press")
    public static let verticalPress = MovementPattern(rawValue: "vertical press")
    public static let horizontalPull = MovementPattern(rawValue: "horizontal pull")
    public static let verticalPull = MovementPattern(rawValue: "vertical pull")
    public static let curl = MovementPattern(rawValue: "curl")
    /// Backticked because `extension` is a Swift keyword.
    public static let `extension` = MovementPattern(rawValue: "extension")
    public static let raise = MovementPattern(rawValue: "raise")
    public static let fly = MovementPattern(rawValue: "fly")
    public static let shrug = MovementPattern(rawValue: "shrug")
    public static let rotation = MovementPattern(rawValue: "rotation")
    public static let flexion = MovementPattern(rawValue: "flexion")
    public static let carry = MovementPattern(rawValue: "carry")
    public static let plyometric = MovementPattern(rawValue: "plyometric")
    public static let olympic = MovementPattern(rawValue: "olympic")
    public static let cardio = MovementPattern(rawValue: "cardio")
    public static let stretch = MovementPattern(rawValue: "stretch")

    public static let known: [MovementPattern] = [
        .squat, .hinge, .lunge, .horizontalPress, .verticalPress,
        .horizontalPull, .verticalPull, .curl, .`extension`, .raise, .fly,
        .shrug, .rotation, .flexion, .carry, .plyometric, .olympic,
        .cardio, .stretch,
    ]
}

/// Whether the movement pushes, pulls, or holds. Depends on: `ExtensibleTaxonomy`.
public struct ForceType: ExtensibleTaxonomy {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = Self.canonicalized(rawValue) }

    public static let push = ForceType(rawValue: "push")
    public static let pull = ForceType(rawValue: "pull")
    public static let `static` = ForceType(rawValue: "static")

    public static let known: [ForceType] = [.push, .pull, .static]
}

/// Whether the movement works one joint or many. Compounds lead a session.
/// Depends on: `ExtensibleTaxonomy`.
public struct Mechanic: ExtensibleTaxonomy {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = Self.canonicalized(rawValue) }

    public static let compound = Mechanic(rawValue: "compound")
    public static let isolation = Mechanic(rawValue: "isolation")

    public static let known: [Mechanic] = [.compound, .isolation]
}

/// Roughly how much training experience a movement asks for.
///
/// Reported alongside an exercise so whoever chooses it can weigh that against
/// the lifter's stated experience. Derived from mechanic and equipment when the
/// source data does not state it. Depends on: `ExtensibleTaxonomy`.
public struct Difficulty: ExtensibleTaxonomy {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = Self.canonicalized(rawValue) }

    public static let beginner = Difficulty(rawValue: "beginner")
    public static let intermediate = Difficulty(rawValue: "intermediate")
    public static let advanced = Difficulty(rawValue: "advanced")

    public static let known: [Difficulty] = [.beginner, .intermediate, .advanced]
}

/// The broad kind of work — lifting, cardio, or stretching.
///
/// Filter on it through `ExerciseFilter` when a question is only about
/// resistance training. Depends on: `ExtensibleTaxonomy`.
public struct ExerciseCategory: ExtensibleTaxonomy {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = Self.canonicalized(rawValue) }

    public static let strength = ExerciseCategory(rawValue: "strength")
    public static let olympic = ExerciseCategory(rawValue: "olympic weightlifting")
    public static let powerlifting = ExerciseCategory(rawValue: "powerlifting")
    public static let plyometrics = ExerciseCategory(rawValue: "plyometrics")
    public static let strongman = ExerciseCategory(rawValue: "strongman")
    public static let cardio = ExerciseCategory(rawValue: "cardio")
    public static let stretching = ExerciseCategory(rawValue: "stretching")

    public static let known: [ExerciseCategory] = [
        .strength, .olympic, .powerlifting, .plyometrics, .strongman,
        .cardio, .stretching,
    ]

    /// Categories that count as resistance training, as opposed to cardio or
    /// stretching.
    ///
    /// It backs `Exercise.isResistanceTraining`, and it is public so a report
    /// that counts only resistance work can *name* what it counted from the
    /// same list it filtered on — a report that spelled the four categories out
    /// in its own prose would start lying the day this set changed.
    public static let resistance: Set<ExerciseCategory> = [
        .strength, .olympic, .powerlifting, .strongman,
    ]
}
