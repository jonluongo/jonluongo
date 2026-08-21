import Foundation
import LiftingKit

/// One entry of a session in the order it is trained: a movement performed on
/// its own, or a group performed as rounds.
///
/// **What it does.** Gives a reader one thing to iterate. The logging screen
/// walks these rather than the session's exercises, so an ungrouped exercise and
/// a group each reach the drawing that suits them.
///
/// **What it depends on.** `PlannedExercise` from Store and `ExerciseGroup`.
enum SessionEntry: Identifiable {
    case exercise(PlannedExercise)
    case group(ExerciseGroup)

    /// The group this entry is, when it holds `exercise`. `nil` otherwise —
    /// including when this entry *is* that exercise, performed on its own.
    ///
    /// Asked by a caller holding a movement and no context: the rest sheet logs
    /// a set without knowing which entry it came from, and which clock starts
    /// depends on whether it was performed in rounds.
    func groupContaining(_ exercise: PlannedExercise) -> ExerciseGroup? {
        guard case .group(let group) = self,
            group.members.contains(where: { $0 === exercise })
        else { return nil }
        return group
    }

    /// The group this entry is, or `nil` when it is a single exercise.
    ///
    /// Named to match `PlanDocumentEntry.group`, which answers the same question
    /// about the same idea on the other side of the seam.
    var group: ExerciseGroup? {
        switch self {
        case .exercise: nil
        case .group(let group): group
        }
    }

    var id: String {
        switch self {
        case .exercise(let exercise): "exercise-\(exercise.persistentModelID)"
        case .group(let group): "group-\(group.ordinal)"
        }
    }
}

/// A superset, tri-set or giant set as the store holds it: the movements, in
/// round order, and the rest taken after the round.
///
/// **What it does.** Answers the questions a screen asks about a group — what it
/// is called, how long to rest when a round finishes, and what to do next.
///
/// **A group needs no row of its own.** Members share a `groupOrdinal` and sit
/// next to each other in `order`; a round is the *N*th working set of each, taken
/// in that order. The rest is on the member the round ends with, because that is
/// where the clock actually runs — nothing is rested after the others.
///
/// **What it depends on.** `PlannedExercise` and `PlannedSet` from Store, and
/// `ExerciseID` from LiftingKit. It never writes and decides nothing: a group
/// exists because a plan said so.
struct ExerciseGroup: Identifiable {

    /// Which group of its session this is, from 1.
    let ordinal: Int
    /// The group's letter within its session — `A` for the first, `B` for the
    /// next.
    let letter: String
    /// The movements in the order they are performed within a round. Two or
    /// more, because the format cannot state fewer.
    let members: [PlannedExercise]

    var id: Int { ordinal }

    /// The rest taken after each round, or `nil` when the plan prescribed none.
    var restSeconds: Int? { members.last?.restSeconds }

    /// The exercise whose clock this group follows. The user's own rest is
    /// kept per exercise, and the group's rest is the one after its last
    /// movement, so that is the exercise a choice about this group is recorded
    /// against.
    var restKey: ExerciseID? { members.last?.exerciseID }

    /// The set to do next after performing `set` of `member`, or `nil` when the
    /// group has nothing waiting.
    ///
    /// **A superset is trained across its movements and drawn down them.** Each
    /// movement gets its own panel, which is what reads — but it means the order
    /// the work is done in runs *across* the panels while the order it is drawn
    /// in runs down them. Ticking the first fly and then looking for the first
    /// pushdown means scrolling past two more fly rows to reach it.
    ///
    /// This answers only *what is next*, from the grouping the plan already
    /// prescribed. When the round is finished it is the first movement's next
    /// set, which is where the next round starts.
    ///
    /// `nil` when every set of the group has been performed, or when the
    /// position has no answer — a movement prescribed fewer sets than its
    /// partner simply has none to offer, and the user is left where he is
    /// rather than sent somewhere arbitrary.
    func setAfter(_ set: PlannedSet, of member: PlannedExercise) -> PlannedSet? {
        guard let memberIndex = members.firstIndex(where: { $0 === member }) else { return nil }
        let working = members.map(\.workingSets)
        guard let position = working[memberIndex].firstIndex(where: { $0 === set })
        else { return nil }

        // The rest of this round, then the next round from the top.
        for index in (memberIndex + 1)..<members.count where position < working[index].count {
            let candidate = working[index][position]
            if !candidate.hasBeenPerformed { return candidate }
        }
        let nextPosition = position + 1
        for index in members.indices where nextPosition < working[index].count {
            let candidate = working[index][nextPosition]
            if !candidate.hasBeenPerformed { return candidate }
        }
        return nil
    }

    /// Whether the round at `position` is finished — every movement of it
    /// performed.
    ///
    /// **This is the one behavioural difference a group makes**, and the whole
    /// reason the grouping is worth expressing: resting only after the round is
    /// what a superset *is*, so performing one movement starts no clock, because
    /// the next follows immediately.
    func isRoundComplete(at position: Int) -> Bool {
        members.allSatisfy { member in
            let working = member.workingSets
            guard position < working.count else { return true }
            return working[position].hasBeenPerformed
        }
    }
}

/// Reads a session's exercises as the entries they were prescribed as.
///
/// **What it does.** Turns a flat, ordered list of movements back into
/// ungrouped exercises and groups, by the `groupOrdinal` they share. Members are
/// contiguous by construction, so a run of them is one group.
///
/// **What it depends on.** `PlannedExercise` from Store. It decides nothing:
/// the app never groups anything, and a session whose exercises share no ordinal
/// is a session of plain movements.
enum SessionGrouping {

    /// The entries of a session, in the order they are trained.
    static func entries(of exercises: [PlannedExercise]) -> [SessionEntry] {
        var entries: [SessionEntry] = []
        var pending: [PlannedExercise] = []
        var groupsSeen = 0

        func flush() {
            guard !pending.isEmpty else { return }
            defer { pending = [] }
            // A group of one cannot be prescribed — the format refuses it — but
            // one can survive a member being removed, and a card labelled "A"
            // with a single movement in it is a lie the screen would tell.
            guard pending.count > 1 else {
                entries.append(.exercise(pending[0]))
                return
            }
            groupsSeen += 1
            entries.append(.group(ExerciseGroup(
                ordinal: pending[0].groupOrdinal ?? groupsSeen,
                letter: letter(at: groupsSeen - 1),
                members: pending)))
        }

        for exercise in exercises.sorted(by: { $0.order < $1.order }) {
            guard let group = exercise.groupOrdinal else {
                flush()
                entries.append(.exercise(exercise))
                continue
            }
            if pending.first?.groupOrdinal != group { flush() }
            pending.append(exercise)
        }
        flush()
        return entries
    }

    /// `A`, `B`, `C` … and past `Z`, `AA`. A session with twenty-six groups in
    /// it is not a session anyone should be given, but a crash would be the
    /// app's fault rather than the plan's.
    private static func letter(at index: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        guard index >= alphabet.count else { return String(alphabet[index]) }
        return String(alphabet[index / alphabet.count - 1]) + String(alphabet[index % alphabet.count])
    }
}

extension PlannedSet {

    /// Whether anything has been recorded against this prescription.
    ///
    /// **There is no `isCompleted` to read.** A performed row exists only if it
    /// happened, so its presence is the fact — which is what removed the
    /// boolean, and the seeded rows that made one necessary.
    var hasBeenPerformed: Bool { !(performed ?? []).isEmpty }

    /// What was actually done against this prescription, if anything.
    var record: PerformedSet? { (performed ?? []).first }
}
