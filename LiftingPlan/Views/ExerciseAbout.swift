import Foundation
import LiftingKit

/// One thing the catalog states about a movement, ready to draw as a row.
///
/// **What it does.** Carries the name of the fact and the fact itself, both
/// already turned into words. The label leads here — the opposite of
/// `LifterFactRow` — because on this screen the reader is scanning for a
/// question ("what does this work?") rather than reading a record of himself.
///
/// **How it is used.** `ExerciseAbout` builds them and `ExerciseAboutSections`
/// draws each as a `LabeledContent`. A row exists only for something the
/// catalog actually states.
///
/// **What it depends on.** Foundation, and nothing else.
struct ExerciseFact: Identifiable, Equatable, Sendable {

    /// What the fact is called.
    let label: String

    /// What the catalog says, in the catalog's own words.
    let value: String

    var id: String { label }
}

/// What the bundled catalog knows about one movement, in words.
///
/// **What it does.** Turns an `Exercise` into the rows the info screen prints
/// — the muscles it trains, what it is performed with, how it moves, and how
/// hard it is graded. Only what the entry states: a movement the catalog did
/// not grade produces no difficulty row, not a row reading "unknown", and an
/// entry with no instructions produces an empty list rather than a heading with
/// nothing under it. It states nothing about training and decides nothing —
/// these are the catalog's words, unranked and uninterpreted.
///
/// **How it is used.** `ExerciseAboutSections` calls `facts` and draws the
/// result. It lives apart from the view because a list that must never invent a
/// fact is worth testing against strings.
///
/// **What it depends on.** `Exercise` and the taxonomies from LiftingKit. It
/// reads no store and writes nothing.
enum ExerciseAbout {

    /// Everything the entry states, in reading order: what it trains, what it
    /// needs, and how it is classified.
    ///
    /// Unknown taxonomy values pass straight through — the vocabularies are
    /// open, and a muscle this build has never heard of is still what the data
    /// says, so it is printed rather than dropped.
    static func facts(for exercise: Exercise) -> [ExerciseFact] {
        [
            fact("Primary", list(exercise.primaryMuscles.map(\.rawValue))),
            fact("Also works", list(exercise.secondaryMuscles.map(\.rawValue))),
            fact("Equipment", sentenceCased(exercise.equipment.rawValue)),
            fact("Pattern", sentenceCased(exercise.pattern.rawValue)),
            fact("Mechanic", exercise.mechanic.map { sentenceCased($0.rawValue) }),
            fact("Difficulty", exercise.difficulty.map { sentenceCased($0.rawValue) }),
        ].compactMap(\.self)
    }

    private static func fact(_ label: String, _ value: String?) -> ExerciseFact? {
        guard let value, !value.isEmpty else { return nil }
        return ExerciseFact(label: label, value: value)
    }

    /// Taxonomy values joined in the order the catalog lists them, or `nil`
    /// when there are none. The order is the data's: an entry that names the
    /// chest first has said something a re-sorted list would lose.
    private static func list(_ values: [String]) -> String? {
        let words = values.filter { !$0.isEmpty }.map(sentenceCased)
        return words.isEmpty ? nil : words.joined(separator: ", ")
    }

    /// The first letter raised and nothing else touched — `"ez bar"` becomes
    /// `"Ez bar"` rather than `"EZ Bar"`, because the second is a guess about a
    /// word the catalog wrote in lower case.
    private static func sentenceCased(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
