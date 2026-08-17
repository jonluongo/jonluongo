import Foundation

/// The group a prescribed exercise was performed in, and where in it.
///
/// **What it does.** Says that these movements were trained as rounds rather
/// than one after another — a superset, a tri-set, a giant set. Without it a
/// superset reads back as six unrelated sets, and the fact that they were
/// performed in rounds, with rest only after each round, is gone from the record
/// entirely.
///
/// **How it is used.** `SnapshotPlannedExercise.group` carries one; it is `nil`
/// for an exercise performed on its own, which is nearly every exercise. Every
/// member of a group reports the same group, so an exercise read on its own
/// still says what it was part of — this is a report, and a report restates.
/// Members of one group are the exercises sharing an `id`, in `position` order,
/// and they are written consecutively within their day.
///
/// **What it depends on.** Foundation. It concludes nothing: the grouping was
/// prescribed, never inferred, and nothing here judges whether it was a good
/// idea or whether the rounds were completed.
public struct SnapshotExerciseGroup: Codable, Hashable, Sendable {

    /// The group's identity, shared by every member.
    public let id: UUID
    /// How the group is written on paper — `A` for the first group of its day,
    /// `B` for the next. `notation` is this letter with the position.
    public let letter: String
    /// This exercise's place in the round, from 1.
    public let position: Int
    /// How many exercises the group holds.
    public let size: Int
    /// Rest after each round, in seconds. `nil` when the plan prescribed none —
    /// not zero. It is the group's rest and the only rest a group has: the
    /// members' own `restSeconds` is absent for every one of them but the last,
    /// because nothing is rested between the movements of a round.
    public let restSeconds: Int?

    /// `A1`, `A2` — the notation a lifter reads on a written program.
    public var notation: String { "\(letter)\(position)" }

    public init(id: UUID, letter: String, position: Int, size: Int, restSeconds: Int?) {
        self.id = id
        self.letter = letter
        self.position = position
        self.size = size
        self.restSeconds = restSeconds
    }
}
