import Foundation

/// What one set row is called: what its badge draws, and how it is read aloud.
///
/// **What it does.** Names a row — `1`, `2`, `W` — so a row takes one value
/// rather than a number plus a flag plus a string.
///
/// **How it is used.** `ExerciseLogSection` builds one per row and hands it to
/// `SetRowView`, which draws `badge` in the set column and speaks `spoken` from
/// every control on the row.
///
/// It also held an `A1` / `A2` form, for rows of a group drawn interleaved by
/// round. The movements of a group are drawn as movements now, each with its own
/// numbered rows, so there is no row that needs a notation to say which movement
/// it belongs to.
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
}
