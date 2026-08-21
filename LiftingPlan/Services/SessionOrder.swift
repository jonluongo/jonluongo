import Foundation
import SwiftData
import LiftingKit

/// One row of a session: what was prescribed, and what has been done about it.
///
/// **What it does.** Names a row of the session — which movement, which
/// prescribed set, what that row is called on screen, and whatever has been
/// recorded against it.
///
/// **A row is a prescription, not a record waiting to be filled in.** It used to
/// be the other way round: a row was a stored `LoggedSet` seeded the moment the
/// screen opened, carrying `isCompleted` to say whether it meant anything, and
/// `reps` defaulting to zero. A row is now the `PlannedSet` the coach wrote,
/// with `record` present only once the lifter has actually done it.
///
/// **What it depends on.** `PlannedExercise` and `PlannedSet` from Store, and
/// `SetIdentity` for what the row is called.
struct TrainingSlot: Identifiable {

    let exercise: PlannedExercise
    let planned: PlannedSet
    /// What the row is called on screen.
    let identity: SetIdentity
    /// Which working set of its movement this is, counting warm-ups out. A ramp
    /// states its sets one at a time, so the third row of a movement is the
    /// third prescription.
    let workingNumber: Int

    /// What the lifter actually did here, or `nil` while he has not.
    var record: PerformedSet? { planned.record }
    /// Whether this row is in the record.
    var isDone: Bool { planned.hasBeenPerformed }

    var id: PersistentIdentifier { planned.persistentModelID }
}

/// The order a session is actually trained in.
///
/// **What it does.** Flattens a session into the sequence of rows the lifter
/// works through: each exercise's sets in order, and a group's rows *across* its
/// movements, round by round, which is what a superset is. It answers one
/// further question — what is next — as the first row nobody has done.
///
/// **It decides nothing.** The order comes from the grouping the plan
/// prescribed, read through `SessionGrouping`, which is the one place in the app
/// that says what was written as a group. A warm-up belongs to the movement it
/// warms up and comes before that movement's working sets; it is not part of a
/// round, because nobody warms up between rounds.
///
/// **What it depends on.** `Session` and `SessionGrouping`. It writes nothing.
enum SessionOrder {

    /// Every row of the session, in the order it is trained.
    static func trainingOrder(of session: Session) -> [TrainingSlot] {
        SessionGrouping.entries(of: session.orderedExercises).flatMap(slots(of:))
    }

    /// The next row nobody has done, or `nil` when the session is filled in.
    ///
    /// "Next" is by the order the work is done in rather than by time: a lifter
    /// who skipped a row and came back to it is looking at the row he skipped.
    static func next(in session: Session) -> TrainingSlot? {
        trainingOrder(of: session).first { !$0.isDone }
    }

    private static func slots(of entry: SessionEntry) -> [TrainingSlot] {
        switch entry {
        case .exercise(let exercise):
            return slots(of: exercise)
        case .group(let group):
            return slots(of: group)
        }
    }

    /// One movement's rows, in the order they are prescribed.
    private static func slots(of exercise: PlannedExercise) -> [TrainingSlot] {
        exercise.orderedSets.enumerated().map { index, set in
            TrainingSlot(
                exercise: exercise, planned: set,
                identity: identity(of: set, at: index, in: exercise),
                workingNumber: workingNumber(at: index, in: exercise))
        }
    }

    /// A group's rows, in the order they are trained: every warm-up first, then
    /// the working sets round by round across the members.
    ///
    /// Warm-ups lead because nobody warms up between rounds — they belong to the
    /// movement they warm up, and the rounds start once the bar is loaded.
    private static func slots(of group: ExerciseGroup) -> [TrainingSlot] {
        let perMember = group.members.map(slots(of:))
        let warmups = perMember.flatMap { $0.filter { $0.planned.isWarmup } }
        let working = perMember.map { $0.filter { !$0.planned.isWarmup } }

        var rounds: [TrainingSlot] = []
        let longest = working.map(\.count).max() ?? 0
        for position in 0..<longest {
            for member in working where position < member.count {
                rounds.append(member[position])
            }
        }
        return warmups + rounds
    }

    /// What a row is called: warm-ups are named as such, and working sets are
    /// numbered among themselves, so a warm-up never takes a set number.
    private static func identity(
        of set: PlannedSet, at index: Int, in exercise: PlannedExercise
    ) -> SetIdentity {
        set.isWarmup ? .warmup : .working(workingNumber(at: index, in: exercise))
    }

    /// How many working sets of this movement have been reached, this one
    /// included. A warm-up takes the number of the working set it precedes,
    /// which is the prescription it is warming up for.
    private static func workingNumber(at index: Int, in exercise: PlannedExercise) -> Int {
        max(1, exercise.orderedSets.prefix(index + 1).count { !$0.isWarmup })
    }
}
