import Foundation

/// One thing somebody stated, ready to draw as a row: what it is called, and
/// what it says.
///
/// **What it does.** Carries two strings that have already been resolved to
/// words — `label` names the fact, `value` is the fact — and identifies itself
/// by the label, because a list never states the same fact twice.
///
/// **How it is used.** `AccountRecord` builds them from the lifter's record,
/// `ExerciseAbout` from the catalog's entry for a movement, and `RoutineFacts`
/// from the shape a plan was given. All three draw through `FactRow`, which is
/// why they are one type: three structs with the same two strings, drawn by the
/// same row, were three names for one thing, and the doc comments on two of them
/// had already drifted into contradicting each other about which way round they
/// read.
///
/// **A row exists only for a fact somebody stated.** There is no row meaning
/// "empty" and none meaning "unknown" — a page of those says nothing at length,
/// and the app must never print a plausible default for a fact nobody gave it.
/// What is missing is named elsewhere, in a sentence, or not at all.
///
/// **What it depends on.** Foundation, and nothing else. It holds no model and
/// no id of one.
/// **It survived the account page it was written for.** That screen listed the
/// lifter as nine labelled fields; it renders `user.md` now, and nothing about
/// him is a row any more. This still has a caller: `ExerciseAbout` draws what
/// the *catalog* knows about a movement — its target, its equipment, its
/// pattern — and those are facts with labels in the same way. It was deleted
/// with the account page and put back the moment the compiler named the second
/// caller.
struct StatedFact: Identifiable, Equatable, Sendable {

    /// What the fact is called, and anything qualifying it.
    let label: String

    /// The fact, in the words or the units it was stated in.
    let value: String

    var id: String { label }
}
