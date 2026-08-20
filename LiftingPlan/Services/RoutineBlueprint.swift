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
/// Absences stay absent: an unnamed block has an empty `title`, a week the
/// plan did not name has a `nil` `label`, and a block the coach wrote no note
/// about has `nil` `notes` rather than an empty one.
struct RoutineBlueprint: Equatable {
    /// Short name for the block. Empty when the plan did not name it.
    var title: String = ""
    var goal: String = ""
    /// What the coach wrote alongside the block, in his own words. `nil` when
    /// the plan stated none — and carried rather than dropped, because it is the
    /// one thing in a plan nobody but its author could have written.
    var notes: String?
    /// How long a session in this block runs. `nil` when the plan did not say.
    var durationMinutes: Int?
    /// When the plan was written, as its document stated. `nil` when the block
    /// did not come from one. Distinct from the start date the mapping is given,
    /// which is when it arrived.
    var generatedAt: Date?
    /// The block's weeks, in the order they are to be trained. A week's
    /// position here is its ordinal.
    var weeks: [BlockBlueprint]

    /// How many weeks the block runs: the weeks it actually holds. Derived
    /// rather than carried, so a stated length and the training that arrived
    /// cannot disagree.
    var weekCount: Int { weeks.count }

    /// Every training day of the block, in order. The days a block trains are a
    /// restatement of the days it prescribes, across all of its weeks.
    var days: [DayBlueprint] { weeks.flatMap(\.days) }
}

extension RoutineBlueprint {

    /// A block of a single week, stated as its days.
    ///
    /// The single-week case is the ordinary one and should not have to name a
    /// week to say so. The week this makes has no label and is not a deload,
    /// because the caller said neither.
    init(
        title: String = "", goal: String = "", notes: String? = nil,
        durationMinutes: Int? = nil, generatedAt: Date? = nil,
        days: [DayBlueprint]
    ) {
        self.init(
            title: title, goal: goal, notes: notes,
            durationMinutes: durationMinutes, generatedAt: generatedAt,
            weeks: [BlockBlueprint(days: days)]
        )
    }
}

/// One week within a `RoutineBlueprint`.
///
/// Weeks are held one at a time because they differ — a deload prescribes
/// genuinely less work than the week before it, not the same work at a lower
/// load. `label` is `nil` when the plan did not name the week: "Week 3" is
/// where a week sits, which the reader knows, not something the plan said.
/// Depends on: `DayBlueprint`.
struct BlockBlueprint: Equatable {
    var label: String?
    var isDeload: Bool
    var days: [DayBlueprint]

    init(label: String? = nil, isDeload: Bool = false, days: [DayBlueprint]) {
        self.label = label
        self.isDeload = isDeload
        self.days = days
    }
}

extension RoutineBlueprint {
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
            notes: notes,
            startDate: startDate,
            generatedAt: generatedAt,
            weekCount: weekCount,
            weekdays: Set(days.map(\.weekday)),
            durationMinutes: durationMinutes,
            catalogVersion: catalogVersion
        )
        plan.weeks = weeks.enumerated().map { index, week in
            Self.makeTrainingWeek(week, ordinal: index + 1)
        }
        return plan
    }

    /// One block of the routine, built on its own.
    ///
    /// The whole-routine path builds every block through this, and so does the
    /// import that adds next week's block to a routine already in the store —
    /// which is what keeps a block written this week identical in the store to
    /// one written as part of a longer plan.
    static func makeTrainingWeek(_ week: BlockBlueprint, ordinal: Int) -> TrainingWeek {
        let trainingWeek = TrainingWeek(
            ordinal: ordinal,
            // The store holds an unnamed week as an empty label, which is
            // what it already means there; no name is invented for it.
            label: week.label ?? "",
            isDeload: week.isDeload
        )
        trainingWeek.days = week.days.map(Self.makeWorkoutDay)
        return trainingWeek
    }

    /// One day's prescriptions, in the order they are to be trained, with a
    /// group's members carrying the identity that makes them one.
    ///
    /// **A group gets one identity and its members a position within it.** The
    /// group's rest lands on the member the round ends with, because that is
    /// where the rest is taken — nothing is rested after the others, since the
    /// next movement of the round follows immediately. That keeps
    /// `PlannedExercise.restSeconds` meaning exactly what it has always meant
    /// and leaves the group needing no column of its own.
    private static func makeWorkoutDay(_ day: DayBlueprint) -> WorkoutDay {
        let workoutDay = WorkoutDay(
            weekday: day.weekday,
            focus: day.focus,
            durationMinutes: day.durationMinutes,
            icon: day.icon
        )
        var prescribed: [PlannedExercise] = []
        for entry in day.entries {
            switch entry {
            case .exercise(let exercise):
                prescribed.append(makePlannedExercise(prescribed.count, exercise))
            case .group(let group):
                let identity = UUID()
                for (position, exercise) in group.exercises.enumerated() {
                    let planned = makePlannedExercise(prescribed.count, exercise)
                    planned.groupID = identity
                    planned.groupPosition = position
                    planned.restSeconds =
                        position == group.exercises.count - 1 ? group.restSeconds : nil
                    prescribed.append(planned)
                }
            }
        }
        workoutDay.exercises = prescribed
        return workoutDay
    }

    /// One prescription, with its sets stored one at a time only when the plan
    /// listed them that way. A uniform prescription stores no per-set rows —
    /// three sets of eight is a count, not three identical records to sync.
    private static func makePlannedExercise(
        _ order: Int, _ exercise: ExerciseBlueprint
    ) -> PlannedExercise {
        let planned = PlannedExercise(
            exerciseID: exercise.exerciseID,
            displayName: exercise.displayName,
            order: order,
            targetSets: exercise.sets,
            repRange: exercise.repRange,
            suggestedLoad: exercise.suggestedLoad,
            restSeconds: exercise.restSeconds,
            intensity: exercise.intensity,
            tempo: exercise.tempo,
            notes: exercise.notes
        )
        planned.statedSets = exercise.statedSets.enumerated().map { index, set in
            PrescribedSet(
                order: index, repRange: set.repRange, suggestedLoad: set.suggestedLoad,
                intensity: set.intensity, notes: set.notes
            )
        }
        return planned
    }
}

extension RoutineBlueprint {

    /// The producer this type was shaped for: a plan Claude wrote, restated in
    /// the app's own vocabulary.
    ///
    /// This is a rename, not a transformation. Every value crosses unchanged
    /// and in the order the document gave it — including a day with no
    /// exercises, which is a rest day the plan named rather than a gap to fill,
    /// and including the coach's `notes`, which this used to drop on the floor.
    /// It performs no validation: `PlanImporter` confirms the exercise IDs
    /// exist *before* building a blueprint, so nothing half-mapped can reach
    /// the store.
    ///
    /// **Everything the document states about the block crosses.** The keys it
    /// does not are the two that describe the document rather than the training
    /// — `version`, which is spent the moment the document is read, and `id`,
    /// which `PlanImporter` stamps on as `sourceDocumentID` so a re-import is a
    /// no-op.
    init(document: PlanDocument) {
        self.init(
            title: document.title,
            goal: document.goal,
            notes: document.notes,
            durationMinutes: document.durationMinutes,
            generatedAt: document.generatedAt,
            weeks: document.weeks.map { week in
                BlockBlueprint(
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
            icon: day.icon,
            entries: day.entries.map(Self.entryBlueprint)
        )
    }

    /// An entry, in whichever of its two shapes it arrived. A group crosses as
    /// a group: the grouping is a prescription like any other, and flattening it
    /// here would lose the only thing it says.
    private static func entryBlueprint(_ entry: PlanDocumentEntry) -> EntryBlueprint {
        switch entry {
        case .exercise(let exercise):
            .exercise(exerciseBlueprint(exercise))
        case .group(let group):
            .group(GroupBlueprint(
                exercises: group.exercises.map(exerciseBlueprint),
                restSeconds: group.restSeconds
            ))
        }
    }

    private static func exerciseBlueprint(_ exercise: PlanDocumentExercise) -> ExerciseBlueprint {
        ExerciseBlueprint(
            exerciseID: exercise.exerciseID,
            displayName: exercise.displayName,
            repRange: exercise.repRange,
            sets: exercise.sets,
            restSeconds: exercise.restSeconds,
            suggestedLoad: exercise.suggestedLoad,
            tempo: exercise.tempo,
            notes: exercise.notes,
            intensity: exercise.intensity,
            statedSets: exercise.statedSets
        )
    }
}
