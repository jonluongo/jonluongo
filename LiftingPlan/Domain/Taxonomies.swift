import Foundation

/// A muscle targeted by an exercise, as named by the bundled catalog.
///
/// Use `primary` and `secondary` collections on `Exercise` rather than
/// constructing these directly. Depends on: `ExtensibleTaxonomy`.
struct MuscleGroup: ExtensibleTaxonomy {
    let rawValue: String
    init(rawValue: String) { self.rawValue = Self.canonicalized(rawValue) }

    static let abdominals = MuscleGroup(rawValue: "abdominals")
    static let abductors = MuscleGroup(rawValue: "abductors")
    static let adductors = MuscleGroup(rawValue: "adductors")
    static let biceps = MuscleGroup(rawValue: "biceps")
    static let calves = MuscleGroup(rawValue: "calves")
    static let chest = MuscleGroup(rawValue: "chest")
    static let forearms = MuscleGroup(rawValue: "forearms")
    static let glutes = MuscleGroup(rawValue: "glutes")
    static let hamstrings = MuscleGroup(rawValue: "hamstrings")
    static let lats = MuscleGroup(rawValue: "lats")
    static let lowerBack = MuscleGroup(rawValue: "lower back")
    static let middleBack = MuscleGroup(rawValue: "middle back")
    static let neck = MuscleGroup(rawValue: "neck")
    static let quadriceps = MuscleGroup(rawValue: "quadriceps")
    static let shoulders = MuscleGroup(rawValue: "shoulders")
    static let traps = MuscleGroup(rawValue: "traps")
    static let triceps = MuscleGroup(rawValue: "triceps")

    static let known: [MuscleGroup] = [
        .abdominals, .abductors, .adductors, .biceps, .calves, .chest,
        .forearms, .glutes, .hamstrings, .lats, .lowerBack, .middleBack,
        .neck, .quadriceps, .shoulders, .traps, .triceps,
    ]
}

/// What the lifter needs to hand to perform an exercise.
///
/// Drives plan generation filtering. Depends on: `ExtensibleTaxonomy`.
struct EquipmentType: ExtensibleTaxonomy {
    let rawValue: String
    init(rawValue: String) { self.rawValue = Self.canonicalized(rawValue) }

    static let bodyweight = EquipmentType(rawValue: "bodyweight")
    static let barbell = EquipmentType(rawValue: "barbell")
    static let dumbbell = EquipmentType(rawValue: "dumbbell")
    static let kettlebell = EquipmentType(rawValue: "kettlebell")
    static let cable = EquipmentType(rawValue: "cable")
    static let machine = EquipmentType(rawValue: "machine")
    static let band = EquipmentType(rawValue: "band")
    static let ezBar = EquipmentType(rawValue: "ez bar")
    static let trapBar = EquipmentType(rawValue: "trap bar")
    static let medicineBall = EquipmentType(rawValue: "medicine ball")
    static let plate = EquipmentType(rawValue: "plate")
    static let suspension = EquipmentType(rawValue: "suspension")
    static let sled = EquipmentType(rawValue: "sled")
    static let cardioMachine = EquipmentType(rawValue: "cardio machine")
    static let other = EquipmentType(rawValue: "other")

    static let known: [EquipmentType] = [
        .bodyweight, .barbell, .dumbbell, .kettlebell, .cable, .machine,
        .band, .ezBar, .trapBar, .medicineBall, .plate, .suspension,
        .sled, .cardioMachine, .other,
    ]
}

/// The movement pattern an exercise trains, used to build balanced sessions
/// and to choose substitutes. Depends on: `ExtensibleTaxonomy`.
struct MovementPattern: ExtensibleTaxonomy {
    let rawValue: String
    init(rawValue: String) { self.rawValue = Self.canonicalized(rawValue) }

    static let squat = MovementPattern(rawValue: "squat")
    static let hinge = MovementPattern(rawValue: "hinge")
    static let lunge = MovementPattern(rawValue: "lunge")
    static let horizontalPress = MovementPattern(rawValue: "horizontal press")
    static let verticalPress = MovementPattern(rawValue: "vertical press")
    static let horizontalPull = MovementPattern(rawValue: "horizontal pull")
    static let verticalPull = MovementPattern(rawValue: "vertical pull")
    static let curl = MovementPattern(rawValue: "curl")
    /// Backticked because `extension` is a Swift keyword.
    static let `extension` = MovementPattern(rawValue: "extension")
    static let raise = MovementPattern(rawValue: "raise")
    static let fly = MovementPattern(rawValue: "fly")
    static let shrug = MovementPattern(rawValue: "shrug")
    static let rotation = MovementPattern(rawValue: "rotation")
    static let flexion = MovementPattern(rawValue: "flexion")
    static let carry = MovementPattern(rawValue: "carry")
    static let plyometric = MovementPattern(rawValue: "plyometric")
    static let olympic = MovementPattern(rawValue: "olympic")
    static let cardio = MovementPattern(rawValue: "cardio")
    static let stretch = MovementPattern(rawValue: "stretch")

    static let known: [MovementPattern] = [
        .squat, .hinge, .lunge, .horizontalPress, .verticalPress,
        .horizontalPull, .verticalPull, .curl, .`extension`, .raise, .fly,
        .shrug, .rotation, .flexion, .carry, .plyometric, .olympic,
        .cardio, .stretch,
    ]
}

/// Whether the movement pushes, pulls, or holds. Depends on: `ExtensibleTaxonomy`.
struct ForceType: ExtensibleTaxonomy {
    let rawValue: String
    init(rawValue: String) { self.rawValue = Self.canonicalized(rawValue) }

    static let push = ForceType(rawValue: "push")
    static let pull = ForceType(rawValue: "pull")
    static let `static` = ForceType(rawValue: "static")

    static let known: [ForceType] = [.push, .pull, .static]
}

/// Whether the movement works one joint or many. Compounds lead a session.
/// Depends on: `ExtensibleTaxonomy`.
struct Mechanic: ExtensibleTaxonomy {
    let rawValue: String
    init(rawValue: String) { self.rawValue = Self.canonicalized(rawValue) }

    static let compound = Mechanic(rawValue: "compound")
    static let isolation = Mechanic(rawValue: "isolation")

    static let known: [Mechanic] = [.compound, .isolation]
}

/// Roughly how much training experience a movement asks for.
///
/// Used to match exercise selection to the lifter's stated experience so a
/// beginner is not handed a snatch. Derived from mechanic and equipment when
/// the source data does not state it. Depends on: `ExtensibleTaxonomy`.
struct Difficulty: ExtensibleTaxonomy {
    let rawValue: String
    init(rawValue: String) { self.rawValue = Self.canonicalized(rawValue) }

    static let beginner = Difficulty(rawValue: "beginner")
    static let intermediate = Difficulty(rawValue: "intermediate")
    static let advanced = Difficulty(rawValue: "advanced")

    static let known: [Difficulty] = [.beginner, .intermediate, .advanced]
}

/// The broad kind of work, used to keep cardio and stretching out of
/// resistance-training slots. Depends on: `ExtensibleTaxonomy`.
struct ExerciseCategory: ExtensibleTaxonomy {
    let rawValue: String
    init(rawValue: String) { self.rawValue = Self.canonicalized(rawValue) }

    static let strength = ExerciseCategory(rawValue: "strength")
    static let olympic = ExerciseCategory(rawValue: "olympic weightlifting")
    static let powerlifting = ExerciseCategory(rawValue: "powerlifting")
    static let plyometrics = ExerciseCategory(rawValue: "plyometrics")
    static let strongman = ExerciseCategory(rawValue: "strongman")
    static let cardio = ExerciseCategory(rawValue: "cardio")
    static let stretching = ExerciseCategory(rawValue: "stretching")

    static let known: [ExerciseCategory] = [
        .strength, .olympic, .powerlifting, .plyometrics, .strongman,
        .cardio, .stretching,
    ]

    /// Categories that count as resistance training for plan generation.
    static let resistance: Set<ExerciseCategory> = [
        .strength, .olympic, .powerlifting, .strongman,
    ]
}
