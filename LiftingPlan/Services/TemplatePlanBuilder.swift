import Foundation

/// Deterministic plan generator used when the on-device model is unavailable
/// (e.g. a simulator without Apple Intelligence) or as a safety net if a model
/// call fails. It builds a sensible split from the user's inputs so the whole
/// app — timers, logging, progression — is fully usable everywhere.
enum TemplatePlanBuilder {

    /// Build a week of training for the given preferences.
    static func build(
        weekdays: [Weekday],
        durationMinutes: Int,
        equipment: Equipment,
        experience: ExperienceLevel
    ) -> PlanBlueprint {
        let orderedDays = weekdays.sorted()
        guard !orderedDays.isEmpty else { return PlanBlueprint(days: []) }

        let split = splitTemplate(forDayCount: orderedDays.count)
        // Compact rest keeps a casual lifter's intensity up; scale a little with duration.
        let compoundRest = durationMinutes >= 60 ? 120 : 90
        let accessoryRest = durationMinutes >= 60 ? 75 : 60
        let setBump = experience == .beginner ? -1 : (experience == .advanced ? 1 : 0)

        let days = orderedDays.enumerated().map { index, weekday -> DayBlueprint in
            let focus = split[index % split.count]
            let exercises = exercises(
                for: focus,
                equipment: equipment,
                durationMinutes: durationMinutes,
                compoundRest: compoundRest,
                accessoryRest: accessoryRest,
                setBump: setBump
            )
            return DayBlueprint(
                weekday: weekday,
                focus: focus,
                durationMinutes: durationMinutes,
                exercises: exercises
            )
        }
        return PlanBlueprint(days: days)
    }

    /// Choose a training split appropriate for how many days per week.
    static func splitTemplate(forDayCount count: Int) -> [String] {
        switch count {
        case ...1: return ["Full Body"]
        case 2: return ["Upper Body", "Lower Body"]
        case 3: return ["Push", "Pull", "Legs"]
        case 4: return ["Upper Body", "Lower Body", "Push", "Pull"]
        case 5: return ["Push", "Pull", "Legs", "Upper Body", "Lower Body"]
        default: return ["Push", "Pull", "Legs", "Upper Body", "Lower Body", "Full Body"]
        }
    }

    private static func exercises(
        for focus: String,
        equipment: Equipment,
        durationMinutes: Int,
        compoundRest: Int,
        accessoryRest: Int,
        setBump: Int
    ) -> [ExerciseBlueprint] {
        // How many movements fit in the session's time budget.
        let budget = durationMinutes >= 75 ? 6 : (durationMinutes >= 45 ? 5 : 4)
        let catalog = movementCatalog(for: focus, equipment: equipment)
        let chosen = Array(catalog.prefix(budget))

        return chosen.enumerated().map { index, movement in
            let isCompound = index < 2
            let sets = max(2, (isCompound ? 4 : 3) + setBump)
            return ExerciseBlueprint(
                name: movement.name,
                muscleGroup: movement.muscleGroup,
                repRange: isCompound ? "6-10" : "10-15",
                sets: sets,
                restSeconds: isCompound ? compoundRest : accessoryRest,
                suggestedWeight: nil,
                tempo: isCompound ? "3-0-1-0" : "2-0-1-0",
                notes: isCompound
                    ? "Leave 1–2 reps in reserve; keep the rest timer honest."
                    : "Controlled reps, full range of motion."
            )
        }
    }

    private struct Movement { let name: String; let muscleGroup: String }

    /// A small hand-picked catalog per focus and equipment tier. Ordered so the
    /// first two entries are the day's main compound lifts.
    private static func movementCatalog(for focus: String, equipment: Equipment) -> [Movement] {
        let gym = equipment == .fullGym
        let hasDumbbells = equipment == .fullGym || equipment == .dumbbellsOnly || equipment == .homeMinimal
        let bodyweightOnly = equipment == .bodyweight

        switch focus {
        case "Push":
            if bodyweightOnly {
                return [.init(name: "Push-Up", muscleGroup: "Chest"),
                        .init(name: "Pike Push-Up", muscleGroup: "Shoulders"),
                        .init(name: "Bench Dip", muscleGroup: "Triceps"),
                        .init(name: "Decline Push-Up", muscleGroup: "Chest"),
                        .init(name: "Diamond Push-Up", muscleGroup: "Triceps")]
            }
            return [.init(name: gym ? "Barbell Bench Press" : "Dumbbell Bench Press", muscleGroup: "Chest"),
                    .init(name: gym ? "Overhead Press" : "Dumbbell Shoulder Press", muscleGroup: "Shoulders"),
                    .init(name: "Incline Dumbbell Press", muscleGroup: "Chest"),
                    .init(name: "Lateral Raise", muscleGroup: "Shoulders"),
                    .init(name: "Triceps Extension", muscleGroup: "Triceps"),
                    .init(name: "Push-Up", muscleGroup: "Chest")]
        case "Pull":
            if bodyweightOnly {
                return [.init(name: "Pull-Up", muscleGroup: "Back"),
                        .init(name: "Inverted Row", muscleGroup: "Back"),
                        .init(name: "Chin-Up", muscleGroup: "Biceps"),
                        .init(name: "Superman Hold", muscleGroup: "Lower Back"),
                        .init(name: "Towel Curl", muscleGroup: "Biceps")]
            }
            return [.init(name: gym ? "Barbell Row" : "Dumbbell Row", muscleGroup: "Back"),
                    .init(name: gym ? "Lat Pulldown" : "Pull-Up", muscleGroup: "Back"),
                    .init(name: "Face Pull", muscleGroup: "Rear Delts"),
                    .init(name: "Dumbbell Curl", muscleGroup: "Biceps"),
                    .init(name: "Hammer Curl", muscleGroup: "Biceps"),
                    .init(name: "Rear Delt Fly", muscleGroup: "Rear Delts")]
        case "Legs", "Lower Body":
            if bodyweightOnly {
                return [.init(name: "Bulgarian Split Squat", muscleGroup: "Quads"),
                        .init(name: "Single-Leg Glute Bridge", muscleGroup: "Glutes"),
                        .init(name: "Reverse Lunge", muscleGroup: "Quads"),
                        .init(name: "Calf Raise", muscleGroup: "Calves"),
                        .init(name: "Wall Sit", muscleGroup: "Quads")]
            }
            return [.init(name: gym ? "Back Squat" : "Goblet Squat", muscleGroup: "Quads"),
                    .init(name: gym ? "Romanian Deadlift" : "Dumbbell Romanian Deadlift", muscleGroup: "Hamstrings"),
                    .init(name: "Walking Lunge", muscleGroup: "Quads"),
                    .init(name: gym ? "Leg Press" : "Bulgarian Split Squat", muscleGroup: "Quads"),
                    .init(name: "Calf Raise", muscleGroup: "Calves"),
                    .init(name: "Glute Bridge", muscleGroup: "Glutes")]
        case "Upper Body":
            if bodyweightOnly {
                return [.init(name: "Push-Up", muscleGroup: "Chest"),
                        .init(name: "Pull-Up", muscleGroup: "Back"),
                        .init(name: "Pike Push-Up", muscleGroup: "Shoulders"),
                        .init(name: "Inverted Row", muscleGroup: "Back"),
                        .init(name: "Bench Dip", muscleGroup: "Triceps")]
            }
            return [.init(name: gym ? "Barbell Bench Press" : "Dumbbell Bench Press", muscleGroup: "Chest"),
                    .init(name: gym ? "Barbell Row" : "Dumbbell Row", muscleGroup: "Back"),
                    .init(name: hasDumbbells ? "Dumbbell Shoulder Press" : "Pike Push-Up", muscleGroup: "Shoulders"),
                    .init(name: "Lat Pulldown", muscleGroup: "Back"),
                    .init(name: "Dumbbell Curl", muscleGroup: "Biceps"),
                    .init(name: "Triceps Extension", muscleGroup: "Triceps")]
        default: // Full Body
            if bodyweightOnly {
                return [.init(name: "Bulgarian Split Squat", muscleGroup: "Quads"),
                        .init(name: "Push-Up", muscleGroup: "Chest"),
                        .init(name: "Pull-Up", muscleGroup: "Back"),
                        .init(name: "Reverse Lunge", muscleGroup: "Quads"),
                        .init(name: "Plank", muscleGroup: "Core")]
            }
            return [.init(name: gym ? "Back Squat" : "Goblet Squat", muscleGroup: "Quads"),
                    .init(name: gym ? "Barbell Bench Press" : "Dumbbell Bench Press", muscleGroup: "Chest"),
                    .init(name: gym ? "Barbell Row" : "Dumbbell Row", muscleGroup: "Back"),
                    .init(name: gym ? "Romanian Deadlift" : "Dumbbell Romanian Deadlift", muscleGroup: "Hamstrings"),
                    .init(name: hasDumbbells ? "Dumbbell Shoulder Press" : "Pike Push-Up", muscleGroup: "Shoulders"),
                    .init(name: "Plank", muscleGroup: "Core")]
        }
    }
}
