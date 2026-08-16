import Foundation
import LiftingKit

/// A plain-value description of a plan the app has been handed.
///
/// This is the single thing that gets mapped into SwiftData, which keeps that
/// mapping easy to unit-test and leaves exactly one place where a plan can
/// enter the store. Build one from a `PlanDocument` with `init(document:)`,
/// then turn it into a persisted `TrainingPlan` with
/// `makeWorkoutPlan(catalogVersion:startDate:)` below. Depends on:
/// `PlanDocument` from LiftingKit and `DayBlueprint`.
///
/// The block-level facts live here rather than being passed alongside, so a
/// caller cannot hand the mapping a plan's days and someone else's goal.
/// Absences stay absent: an unnamed block has an empty `title`, and a week the
/// plan did not name has a `nil` `label`.
struct PlanBlueprint: Equatable {
    /// Short name for the block. Empty when the plan did not name it.
    var title: String = ""
    var goal: String = ""
    /// How long a session in this block runs. `nil` when the plan did not say.
    var durationMinutes: Int?
    /// The block's weeks, in the order they are to be trained. A week's
    /// position here is its ordinal.
    var weeks: [WeekBlueprint]

    /// How many weeks the block runs: the weeks it actually holds. Derived
    /// rather than carried, so a stated length and the training that arrived
    /// cannot disagree.
    var weekCount: Int { weeks.count }

    /// Every training day of the block, in order. The days a block trains are a
    /// restatement of the days it prescribes, across all of its weeks.
    var days: [DayBlueprint] { weeks.flatMap(\.days) }
}

extension PlanBlueprint {

    /// A block of a single week, stated as its days.
    ///
    /// The single-week case is the ordinary one and should not have to name a
    /// week to say so. The week this makes has no label and is not a deload,
    /// because the caller said neither.
    init(
        title: String = "", goal: String = "", durationMinutes: Int? = nil,
        days: [DayBlueprint]
    ) {
        self.init(
            title: title, goal: goal, durationMinutes: durationMinutes,
            weeks: [WeekBlueprint(days: days)]
        )
    }
}

/// One week within a `PlanBlueprint`.
///
/// Weeks are held one at a time because they differ — a deload prescribes
/// genuinely less work than the week before it, not the same work at a lower
/// load. `label` is `nil` when the plan did not name the week: "Week 3" is
/// where a week sits, which the reader knows, not something the plan said.
/// Depends on: `DayBlueprint`.
struct WeekBlueprint: Equatable {
    var label: String?
    var isDeload: Bool
    var days: [DayBlueprint]

    init(label: String? = nil, isDeload: Bool = false, days: [DayBlueprint]) {
        self.label = label
        self.isDeload = isDeload
        self.days = days
    }
}

/// One training day within a `WeekBlueprint`. Depends on: `Weekday` from
/// Domain, `ExerciseBlueprint`.
struct DayBlueprint: Equatable {
    var weekday: Weekday
    var focus: String
    var durationMinutes: Int?
    var exercises: [ExerciseBlueprint]
}

/// One prescribed movement within a `DayBlueprint`.
///
/// `exerciseID` is the identity that gets persisted onto `PlannedExercise` and
/// is what `PerformanceHistory` joins on; `displayName` is shown to the lifter
/// and carried through for display only. Never resolve or match an exercise by
/// `displayName` — collapsing that distinction back into a single free-text
/// name is exactly the bug this type's shape exists to prevent. Depends on:
/// `ExerciseID`, `Mass` from Domain.
struct ExerciseBlueprint: Equatable {
    var exerciseID: ExerciseID
    var displayName: String
    var repRange: String
    var sets: Int
    var restSeconds: Int?
    var suggestedLoad: Mass?
    var tempo: String?
    var notes: String?
}

extension PlanBlueprint {
    /// Build the SwiftData object graph for this blueprint: a new `TrainingPlan`
    /// holding one `TrainingWeek` per week, in the order they were given.
    ///
    /// **Every value is recorded exactly as given.** Nothing here clamps,
    /// floors, caps, or substitutes: 10 sets stay 10 sets, a 12-minute rest
    /// between heavy singles stays 12 minutes, and an unstated rep range stays
    /// unstated rather than becoming someone's idea of a sensible default.
    /// Whoever wrote the plan made those calls with more context than this
    /// function will ever have, and a silently altered prescription is
    /// indistinguishable from the one that was actually written.
    ///
    /// **Weeks are mapped one for one.** An eight-week block becomes eight
    /// weeks, each with the days it actually prescribes; a week is never
    /// repeated to fill a block out, and a week that was not written is not
    /// invented. A week's ordinal is its position, so nothing has to reconcile
    /// a stated number with where the week sits.
    ///
    /// `catalogVersion` is the `ExerciseCatalogProviding.version` these
    /// exercises were selected from; it is stamped onto the plan so a later
    /// correction to the catalog data can be detected rather than silently
    /// reinterpreting logged work. It has deliberately no default value — the
    /// stamp is only meaningful if every caller states where its exercises came
    /// from, so the compiler asks rather than a wrong value being assumed.
    ///
    /// `startDate` is when this block becomes the lifter's current one, which
    /// is when it arrived rather than anything the plan itself decided.
    ///
    /// The block's training days are derived from the days it actually
    /// prescribes. That is a restatement of the plan, not a decision about it.
    func makeWorkoutPlan(
        catalogVersion: Int,
        startDate: Date = Date()
    ) -> TrainingPlan {
        let plan = TrainingPlan(
            title: title,
            goal: goal,
            startDate: startDate,
            weekCount: weekCount,
            weekdays: Set(days.map(\.weekday)),
            durationMinutes: durationMinutes,
            catalogVersion: catalogVersion
        )
        plan.weeks = weeks.enumerated().map { index, week in
            let trainingWeek = TrainingWeek(
                ordinal: index + 1,
                // The store holds an unnamed week as an empty label, which is
                // what it already means there; no name is invented for it.
                label: week.label ?? "",
                isDeload: week.isDeload
            )
            trainingWeek.days = week.days.map(Self.makeWorkoutDay)
            return trainingWeek
        }
        return plan
    }

    private static func makeWorkoutDay(_ day: DayBlueprint) -> WorkoutDay {
        let workoutDay = WorkoutDay(
            weekday: day.weekday,
            focus: day.focus,
            durationMinutes: day.durationMinutes
        )
        workoutDay.exercises = day.exercises.enumerated().map { exIndex, ex in
            PlannedExercise(
                exerciseID: ex.exerciseID,
                displayName: ex.displayName,
                order: exIndex,
                targetSets: ex.sets,
                repRange: ex.repRange,
                suggestedLoad: ex.suggestedLoad,
                restSeconds: ex.restSeconds,
                tempo: ex.tempo,
                notes: ex.notes
            )
        }
        return workoutDay
    }
}

extension PlanBlueprint {

    /// The producer this type was shaped for: a plan Claude wrote, restated in
    /// the app's own vocabulary.
    ///
    /// This is a rename, not a transformation. Every value crosses unchanged
    /// and in the order the document gave it — including a day with no
    /// exercises, which is a rest day the plan named rather than a gap to fill.
    /// It performs no validation: `PlanImporter` confirms the exercise IDs
    /// exist *before* building a blueprint, so nothing half-mapped can reach
    /// the store.
    init(document: PlanDocument) {
        self.init(
            title: document.title,
            goal: document.goal,
            durationMinutes: document.durationMinutes,
            weeks: document.weeks.map { week in
                WeekBlueprint(
                    label: week.label,
                    isDeload: week.isDeload,
                    days: week.days.map(Self.dayBlueprint)
                )
            }
        )
    }

    private static func dayBlueprint(_ day: PlanDocumentDay) -> DayBlueprint {
        DayBlueprint(
            weekday: day.weekday,
            focus: day.focus,
            durationMinutes: day.durationMinutes,
            exercises: day.exercises.map { exercise in
                ExerciseBlueprint(
                    exerciseID: exercise.exerciseID,
                    displayName: exercise.displayName,
                    repRange: exercise.repRange,
                    sets: exercise.sets,
                    restSeconds: exercise.restSeconds,
                    suggestedLoad: exercise.suggestedLoad,
                    tempo: exercise.tempo,
                    notes: exercise.notes
                )
            }
        )
    }
}
