import Foundation

/// What one set row is called: what its badge draws, and how it is read aloud.
///
/// **What it does.** Names a row. On its own an exercise's rows are numbered —
/// `1`, `2`, `W` — and inside a group they are the A1 / A2 notation a lifter
/// already reads on a written program. Both are the same thing to a row, so a
/// row takes one value rather than a number plus a flag plus a string.
///
/// **How it is used.** `ExerciseLogSection` and `SupersetLogSection` build one
/// per row and hand it to `SetRowView`, which draws `badge` in the set column
/// and speaks `spoken` from every control on the row. Inside a group `spoken`
/// carries the exercise and the round, because what a row is is carried
/// visually by its position and VoiceOver reads no position.
///
/// **What it depends on.** Foundation. It decides nothing and reads nothing.
struct SetIdentity: Equatable {

    /// What the badge draws: `3`, `W`, `A1`.
    let badge: String

    /// How the row is named aloud, as it reads in a sentence: "working set 3",
    /// "Dumbbell Chest Fly, A1, round 2".
    let spoken: String

    /// A numbered working set of an exercise performed on its own.
    static func working(_ number: Int) -> SetIdentity {
        SetIdentity(badge: "\(number)", spoken: "working set \(number)")
    }

    /// A warm-up, which is not numbered because it is not the work.
    static let warmup = SetIdentity(badge: "W", spoken: "warm-up set")

    /// One movement's row within a round of a group.
    ///
    /// The exercise is named because the badge does not name it: on this card
    /// the name is in the legend at the top, and a lifter looking at row four
    /// reads which movement it is from `A1` against that legend. VoiceOver has
    /// no legend to look at, so the row says it.
    static func inRound(
        _ notation: String, exercise: String, round: Int
    ) -> SetIdentity {
        SetIdentity(
            badge: notation, spoken: "\(exercise), \(notation), round \(round)")
    }

    /// A warm-up on one movement of a group. It belongs to no round, so it
    /// names none.
    static func warmup(_ notation: String, exercise: String) -> SetIdentity {
        SetIdentity(badge: "W", spoken: "\(exercise), \(notation), warm-up set")
    }
}
