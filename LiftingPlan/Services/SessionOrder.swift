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
/// with `record` present only once the user has actually done it.
///
/// **What it depends on.** `PlannedExercise` and `PlannedSet` from Store, and
/// `SetIdentity` for what the row is called.
struct TrainingSlot: Identifiable {

    let exercise: PlannedExercise
    /// The prescription behind this row, or `nil` for a set the user added.
    ///
    /// **Optional because the record may hold work nobody prescribed.** A fifth
    /// set actually performed is the thing this app exists to keep, and while
    /// this was non-optional `addSet` wrote a `PerformedSet` that no row could
    /// be built for — in the store, exported to the coach as real volume, and
    /// drawn nowhere. He pressed *Add extra set* and the table did not change.
    let planned: PlannedSet?
    /// The record of a set nobody prescribed. A prescribed row reads its record
    /// through `planned`; this is the other half, and exactly one of the two is
    /// ever set.
    private let added: PerformedSet?
    /// What the row is called on screen.
    let identity: SetIdentity
    /// Which working set of its movement this is, counting warm-ups out. A ramp
    /// states its sets one at a time, so the third row of a movement is the
    /// third prescription.
    let workingNumber: Int
    /// Warm-ups lead a group and take no set number. Stored rather than read off
    /// `planned`, which an added row does not have.
    let isWarmup: Bool

    let id: PersistentIdentifier

    /// What the user actually did here, or `nil` while he has not.
    var record: PerformedSet? { planned?.record ?? added }
    /// Whether this row is in the record.
    var isDone: Bool { record != nil }
    /// Whether unticking this row removes it. **An added row exists only because
    /// its record does**, so taking the record back leaves nothing to draw —
    /// which is the delete affordance, without a second control that would do
    /// the same thing.
    var vanishesWhenTakenBack: Bool { planned == nil }

    init(
        exercise: PlannedExercise, planned: PlannedSet,
        identity: SetIdentity, workingNumber: Int
    ) {
        self.exercise = exercise
        self.planned = planned
        self.added = nil
        self.identity = identity
        self.workingNumber = workingNumber
        self.isWarmup = planned.isWarmup
        self.id = planned.persistentModelID
    }

    /// A row for a set the user added, which has a record and no prescription.
    init(exercise: PlannedExercise, added: PerformedSet, workingNumber: Int) {
        self.exercise = exercise
        self.planned = nil
        self.added = added
        self.identity = added.isWarmup ? .warmup : .working(workingNumber)
        self.workingNumber = workingNumber
        self.isWarmup = added.isWarmup
        self.id = added.persistentModelID
    }
}

/// The order a session is actually trained in.
///
/// **What it does.** Flattens a session into the sequence of rows the user
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
    /// "Next" is by the order the work is done in rather than by time: a user
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

    /// One movement's rows: what was prescribed, then what he added past it.
    ///
    /// **The added ones come last because that is when they happened.** They are
    /// work done after the prescription ran out, and putting them anywhere else
    /// would claim an order the record does not have.
    private static func slots(of exercise: PlannedExercise) -> [TrainingSlot] {
        let prescribed = exercise.orderedSets.enumerated().map { index, set in
            TrainingSlot(
                exercise: exercise, planned: set,
                identity: identity(of: set, at: index, in: exercise),
                workingNumber: workingNumber(at: index, in: exercise))
        }
        var working = prescribed.filter { !$0.isWarmup }.count
        let added = addedSets(of: exercise).map { performed -> TrainingSlot in
            if !performed.isWarmup { working += 1 }
            return TrainingSlot(
                exercise: exercise, added: performed, workingNumber: working)
        }
        return prescribed + added
    }

    /// Sets recorded against this movement that no prescription is behind, in
    /// the order they were performed.
    private static func addedSets(of exercise: PlannedExercise) -> [PerformedSet] {
        (exercise.performed ?? [])
            .flatMap { $0.sets ?? [] }
            .filter { $0.planned == nil }
            .sorted { $0.completedAt < $1.completedAt }
    }

    /// A group's rows, in the order they are trained: every warm-up first, then
    /// the working sets round by round across the members.
    ///
    /// Warm-ups lead because nobody warms up between rounds — they belong to the
    /// movement they warm up, and the rounds start once the bar is loaded.
    private static func slots(of group: ExerciseGroup) -> [TrainingSlot] {
        let perMember = group.members.map(slots(of:))
        let warmups = perMember.flatMap { $0.filter(\.isWarmup) }
        let working = perMember.map { $0.filter { !$0.isWarmup } }

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
