import Foundation
import LiftingKit

/// One entry of a session in the order it is trained: a movement performed on
/// its own, or a group performed as rounds.
///
/// **What it does.** Gives every screen one thing to iterate. A screen that
/// draws a day walks these rather than the day's exercises, so an ungrouped
/// exercise reaches exactly the view it always did and a group reaches the one
/// that knows about rounds.
///
/// **How it is used.** `WorkoutDay.entries` builds them. `Identifiable` so a
/// `ForEach` can hold them without an index, which is what keeps a row stable
/// while its sets are being edited.
///
/// **What it depends on.** `PlannedExercise` from Store and `ExerciseGroup`.
enum SessionEntry: Identifiable {
    case exercise(PlannedExercise)
    case group(ExerciseGroup)

    var id: String {
        switch self {
        case .exercise(let exercise): "exercise-\(exercise.persistentModelID)"
        case .group(let group): "group-\(group.id)"
        }
    }

    /// The movements this entry prescribes, in order.
    var exercises: [PlannedExercise] {
        switch self {
        case .exercise(let exercise): [exercise]
        case .group(let group): group.members
        }
    }
}

/// A superset, tri-set or giant set as the store holds it: the movements, in
/// round order, and the rest taken after the round.
///
/// **What it does.** Answers the questions a screen asks about a group — what it
/// is called, how long to rest when a round finishes, and whether one just did.
///
/// **How it is used.** Built by `SessionGrouping` and handed to the logging
/// screen and the read-only week. It never writes and decides nothing about
/// training: a group exists because a plan said so.
///
/// **What it depends on.** `PlannedExercise` from Store and `ExerciseID` from
/// LiftingKit.
struct ExerciseGroup: Identifiable {

    /// The group's own identity, shared by its members.
    let id: UUID
    /// The group's letter within its day — `A` for the first, `B` for the next.
    let letter: String
    /// The movements in the order they are performed within a round. Two or
    /// more, because the format cannot state fewer.
    let members: [PlannedExercise]

    /// The rest taken after each round, or `nil` when the plan prescribed none.
    ///
    /// It sits on the member the round ends with, which is where the rest is
    /// actually taken; nothing is rested after the others.
    var restSeconds: Int? { members.last?.restSeconds }

    /// The exercise whose clock the group follows. The lifter's own rest is kept
    /// per exercise, and the group's rest is the one after its last movement, so
    /// that is the exercise a choice about this group is recorded against.
    var restKey: ExerciseID? { members.last?.exerciseID }

    /// Whether any round of this group is finished — every movement of it
    /// ticked.
    ///
    /// This is the one behavioural difference a group makes, and the whole
    /// reason the grouping is worth expressing: resting only after the round is
    /// what a superset *is*, so ticking one movement starts nothing, because the
    /// next follows immediately.
    ///
    /// A round is the sets at one position across the members. A movement
    /// prescribed more sets than its partner still has its later positions
    /// counted — they are rounds of one, which is what the lifter is actually
    /// doing by then.
    ///
    /// It lived in `GroupRounds`, a value type that also built every row of a
    /// screen: the notation, the prescription, the ghost load, the warm-ups
    /// outside the rounds. That screen was replaced by movements drawn as
    /// movements, and this was the only line of it anything still asked for.
    var hasCompleteRound: Bool {
        var rounds: [[LoggedSet]] = []
        for member in members {
            let working = (member.loggedSets ?? [])
                .filter { !$0.isWarmup }
                .sorted { $0.setIndex < $1.setIndex }
            for (position, set) in working.enumerated() {
                while rounds.count <= position { rounds.append([]) }
                rounds[position].append(set)
            }
        }
        return rounds.contains { !$0.isEmpty && $0.allSatisfy(\.isCompleted) }
    }

    /// What the group is called: the standard word for a group of this size,
    /// with its letter. Vocabulary a lifter already reads, not a judgement about
    /// the training.
    var title: String {
        switch members.count {
        case 2: "Superset \(letter)"
        case 3: "Tri-set \(letter)"
        default: "Giant set \(letter)"
        }
    }
}

/// Reads a day's prescriptions back into the entries they were written as.
///
/// **What it does.** Turns a flat, ordered list of `PlannedExercise` into
/// exercises and groups, by collecting neighbours that share a `groupID`. That
/// is a restatement of what the plan said, not a decision: nothing here decides
/// that two exercises belong together, and an exercise with no `groupID` is on
/// its own no matter what sits beside it.
///
/// **How it is used.** Through `WorkoutDay.entries`, by every screen that draws
/// a session. One place, so a day cannot be grouped one way on the logging
/// screen and another on the week.
///
/// **What it depends on.** `PlannedExercise` from Store. Neighbours are
/// collected rather than the whole day being bucketed by identity, so a group
/// whose members somehow arrive apart — a half-synced CloudKit record — degrades
/// into ordinary exercises in the order they were prescribed rather than
/// reordering the day around them.
enum SessionGrouping {

    /// The day's work in order. `exercises` must already be in prescribed order.
    static func entries(of exercises: [PlannedExercise]) -> [SessionEntry] {
        var entries: [SessionEntry] = []
        var index = 0
        var letters = 0

        while index < exercises.count {
            let exercise = exercises[index]
            guard let groupID = exercise.groupID else {
                entries.append(.exercise(exercise))
                index += 1
                continue
            }
            var members: [PlannedExercise] = []
            while index < exercises.count, exercises[index].groupID == groupID {
                members.append(exercises[index])
                index += 1
            }
            // A group of one is not one. The format cannot state it, so this is
            // a record that arrived incomplete: it reads as the exercise it is
            // rather than as a group missing its other half.
            guard members.count > 1 else {
                entries.append(.exercise(members[0]))
                continue
            }
            entries.append(.group(ExerciseGroup(
                id: groupID,
                letter: letter(at: letters),
                members: members.sorted { ($0.groupPosition ?? 0) < ($1.groupPosition ?? 0) }
            )))
            letters += 1
        }
        return entries
    }

    /// The letter for the group at `index`: A, B, … Z, then AA. Spreadsheet
    /// order, because it is the one everybody already reads and it never runs
    /// out.
    private static func letter(at index: Int) -> String {
        var remaining = index
        var letters = ""
        repeat {
            let scalar = UnicodeScalar(UInt8(65 + remaining % 26))
            letters = String(Character(scalar)) + letters
            remaining = remaining / 26 - 1
        } while remaining >= 0
        return letters
    }
}

extension WorkoutDay {

    /// The day's work in the order it is trained, with grouped exercises
    /// collected into the groups they were prescribed as.
    var entries: [SessionEntry] { SessionGrouping.entries(of: orderedExercises) }
}
