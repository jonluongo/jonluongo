import Foundation
import LiftingKit

/// One training day within a `BlockBlueprint`.
///
/// **Its work is a list of entries, not a flat list of exercises**, because an
/// entry may be a group — a superset, a tri-set, a giant set — performed as
/// rounds. `exercises` is that list flattened, in the same order, for the
/// callers that only ever cared which movements a day prescribes. It is derived
/// rather than stored so a day cannot hold two lists that disagree.
///
/// Depends on: `Weekday` from Domain, `EntryBlueprint`.
struct DayBlueprint: Equatable {
    var weekday: Weekday
    var focus: String
    var durationMinutes: Int?
    /// The mark the plan chose for this session. `nil` when it chose none.
    var icon: SessionIcon?
    var entries: [EntryBlueprint]

    /// Every movement the day prescribes, in order, whatever it was grouped
    /// into.
    var exercises: [ExerciseBlueprint] { entries.flatMap(\.exercises) }

    init(
        weekday: Weekday, focus: String = "", durationMinutes: Int? = nil,
        icon: SessionIcon? = nil, entries: [EntryBlueprint] = []
    ) {
        self.weekday = weekday
        self.focus = focus
        self.durationMinutes = durationMinutes
        self.icon = icon
        self.entries = entries
    }

    /// A day of ungrouped exercises, which is nearly every day.
    init(
        weekday: Weekday, focus: String = "", durationMinutes: Int? = nil,
        icon: SessionIcon? = nil, exercises: [ExerciseBlueprint]
    ) {
        self.init(
            weekday: weekday, focus: focus, durationMinutes: durationMinutes,
            icon: icon, entries: exercises.map(EntryBlueprint.exercise)
        )
    }
}

/// One entry of a day: a movement performed on its own, or a group of them
/// performed back to back.
///
/// The same two shapes `PlanDocumentEntry` has, restated in the app's own
/// vocabulary, so the mapping into the store is a rename rather than a
/// reinterpretation. Depends on: `ExerciseBlueprint`, `GroupBlueprint`.
enum EntryBlueprint: Equatable {
    case exercise(ExerciseBlueprint)
    case group(GroupBlueprint)

    var exercises: [ExerciseBlueprint] {
        switch self {
        case .exercise(let exercise): [exercise]
        case .group(let group): group.exercises
        }
    }
}

/// Two or more movements performed as rounds, resting after the round.
///
/// `restSeconds` is the group's and the only rest it has — see
/// `PlannedExercise.restSeconds` for where that lands in the store. Depends on:
/// `ExerciseBlueprint`.
struct GroupBlueprint: Equatable {
    var exercises: [ExerciseBlueprint]
    var restSeconds: Int?
}

/// One prescribed movement within a `DayBlueprint`.
///
/// `exerciseID` is the identity that gets persisted onto `PlannedExercise` and
/// is what `PerformanceHistory` joins on; `displayName` is shown to the lifter
/// and carried through for display only. Never resolve or match an exercise by
/// `displayName` — collapsing that distinction back into a single free-text
/// name is exactly the bug this type's shape exists to prevent.
///
/// `sets` is always how many sets there are. `statedSets` holds them one at a
/// time when the plan listed them and is empty when it prescribed the same work
/// throughout — the ordinary case, which stores no per-set rows. Depends on:
/// `ExerciseID`, `Mass`, `IntensityTarget`, `SetPrescription`.
struct ExerciseBlueprint: Equatable {
    var exerciseID: ExerciseID
    var displayName: String
    var repRange: String
    var sets: Int
    var restSeconds: Int?
    var suggestedLoad: Mass?
    var tempo: String?
    var notes: String?
    /// How hard the work should be. `nil` when the plan named no target.
    var intensity: IntensityTarget?
    /// The sets the plan listed one at a time, in order. Empty when uniform.
    var statedSets: [SetPrescription] = []
}
