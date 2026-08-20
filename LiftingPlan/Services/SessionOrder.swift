import Foundation
import SwiftData
import LiftingKit

/// One set of a session, in the place it is trained.
///
/// **What it does.** Names a row of the day — which movement, which set, and
/// what that set is called on screen — so a screen showing one set at a time has
/// everything it needs without walking the day itself.
///
/// **What it depends on.** `PlannedExercise` and `LoggedSet` from Store, and
/// `SetIdentity` for what the row is called.
struct TrainingSlot: Identifiable {

    let exercise: PlannedExercise
    let set: LoggedSet
    /// What the row is called on screen.
    let identity: SetIdentity
    /// Which working set of its movement this is, counting warm-ups out. It is
    /// what a prescription is looked up by — a ramp states its sets one at a
    /// time, and the third row of a movement is the third prescription.
    let workingNumber: Int

    /// `self` is written out because a property body opening with `set` reads
    /// as the start of a setter to the parser — the same trap `SetRowView`
    /// documents.
    var id: PersistentIdentifier { self.set.persistentModelID }
}

/// The order a session is actually trained in.
///
/// **What it does.** Flattens a day into the sequence of sets the lifter works
/// through: each exercise's rows in order, and a group's rows *across* its
/// movements, round by round, which is what a superset is. It answers one
/// further question — what is next — as the first row nobody has ticked.
///
/// **It decides nothing.** The order comes from the grouping the plan
/// prescribed, read through `SessionGrouping`, which is the one place in the app
/// that says what was written as a group. A warm-up belongs to the movement it
/// warms up and comes before that movement's working sets; it is not part of a
/// round, because nobody warms up between rounds.
///
/// **How it is used.** `RestSheet` shows `next(in:)` and moves on when it is
/// ticked. Nothing else in the app needs the whole order yet, and `trainingOrder`
/// is what makes the answer testable without a screen.
///
/// **What it depends on.** `WorkoutDay` and `SessionGrouping`. It writes
/// nothing.
enum SessionOrder {

    /// Every set of the day, in the order it is trained.
    static func trainingOrder(of day: WorkoutDay) -> [TrainingSlot] {
        day.entries.flatMap(slots(of:))
    }

    /// The next set nobody has ticked, or `nil` when the session is filled in.
    ///
    /// "Next" is by the order the work is done in rather than by time: a lifter
    /// who skipped a row and came back to it is looking at the row he skipped.
    static func next(in day: WorkoutDay) -> TrainingSlot? {
        trainingOrder(of: day).first { !$0.set.isCompleted }
    }

    private static func slots(of entry: SessionEntry) -> [TrainingSlot] {
        switch entry {
        case .exercise(let exercise):
            return ordered(exercise).enumerated().map { index, set in
                TrainingSlot(
                    exercise: exercise, set: set,
                    identity: identity(of: set, at: index, in: exercise),
                    workingNumber: workingNumber(of: set, at: index, in: exercise))
            }
        case .group(let group):
            return slots(of: group)
        }
    }

    /// A group, trained the way a group is: each movement's warm-ups first,
    /// then the rounds, taking one set from each movement in turn.
    ///
    /// A movement prescribed more sets than its partner keeps its later rows;
    /// they are rounds of one, which is what the lifter is actually doing by
    /// then.
    private static func slots(of group: ExerciseGroup) -> [TrainingSlot] {
        var leading: [TrainingSlot] = []
        var trailing: [TrainingSlot] = []
        var working: [[LoggedSet]] = []
        for member in group.members {
            let sets = ordered(member)
            let firstWorking = sets.firstIndex { !$0.isWarmup }
            for (index, set) in sets.enumerated() where set.isWarmup {
                let slot = TrainingSlot(
                    exercise: member, set: set,
                    identity: identity(of: set, at: index, in: member),
                    workingNumber: workingNumber(of: set, at: index, in: member))
                // **A warm-up goes where he put it.** The ones written before
                // the working sets come before the rounds, which is what warming
                // up is. One added afterwards — the menu allows it at any point
                // — used to be hoisted to the front with them, so a lifter
                // halfway through round three was told his next set was a
                // warm-up. It stays after the rounds, which is both where the
                // table draws it and where he asked for it.
                if let firstWorking, index > firstWorking {
                    trailing.append(slot)
                } else {
                    leading.append(slot)
                }
            }
            working.append(sets.filter { !$0.isWarmup })
        }

        var rounds: [TrainingSlot] = []
        let count = working.map(\.count).max() ?? 0
        for round in 0..<count {
            for (position, sets) in working.enumerated() where round < sets.count {
                rounds.append(TrainingSlot(
                    exercise: group.members[position], set: sets[round],
                    identity: .working(round + 1), workingNumber: round + 1))
            }
        }
        return leading + rounds + trailing
    }

    private static func ordered(_ exercise: PlannedExercise) -> [LoggedSet] {
        (exercise.loggedSets ?? []).sorted { $0.setIndex < $1.setIndex }
    }

    /// What a row is called: warm-ups are named as such, and working sets are
    /// numbered among themselves, so a warm-up never takes a set number.
    private static func identity(
        of set: LoggedSet, at index: Int, in exercise: PlannedExercise
    ) -> SetIdentity {
        set.isWarmup ? .warmup : .working(workingNumber(of: set, at: index, in: exercise))
    }

    /// How many working sets of this movement have been reached, this one
    /// included. A warm-up takes the number of the working set it precedes,
    /// which is the prescription it is warming up for.
    private static func workingNumber(
        of set: LoggedSet, at index: Int, in exercise: PlannedExercise
    ) -> Int {
        let counted = ordered(exercise).prefix(index + 1).count { !$0.isWarmup }
        return max(1, counted)
    }
}
