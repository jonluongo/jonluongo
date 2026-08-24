import Foundation

/// What one set actually came to, in the measure its prescription named.
///
/// **What it does.** Carries a performed set's work as one value with three
/// cases, so a set cannot state two measures at once. `WorkMeasure` says which
/// of the three a prescription asks for; this is the answer, and the pair is
/// deliberately the same shape.
///
/// **Why it exists.** The logging path took `reps`, `durationSeconds` and
/// `distance` as three separate optionals and wrote whatever it was handed. Its
/// own doc comment promised the opposite — *which measure is written is decided
/// by what was prescribed, never by what was typed: a hold cannot land in the
/// rep column* — and nothing in the types held anyone to it. The one caller that
/// mattered switched on the prescription correctly and then flattened its answer
/// into positional optionals, where a second caller could pass all three, or the
/// wrong one, and the compiler would agree. That is the `isTimed`-beside-
/// `isDistance` shape `WorkMeasure` was written to remove, one level down.
///
/// **How it is used.** A row builds one from the measure it drew and the text in
/// its field; the store asks for `reps`, `durationSeconds` and `distance` and
/// gets exactly one of them filled. The fan-out happens here, once, and is
/// exhaustive — a fourth measure will not compile until this has been told what
/// to do with it.
///
/// **A blank field is `nil`, not zero.** He ticked the set without saying how
/// many, which is not the same as saying none — a hold that was not timed and a
/// carry that did not happen are absences, and the store models them honestly.
///
/// **What it depends on.** `Distance` and `WorkMeasure`. It decides nothing: the
/// measure comes from the prescription, never from what the user typed.
public enum WorkDone: Hashable, Sendable {

    /// Counted, in reps.
    case repetitions(Int?)

    /// Held, in seconds.
    case time(seconds: Int?)

    /// Carried, over the distance and unit it was prescribed in.
    case distance(Distance?)

    /// The reps this set did, or `nil` when it was not counted.
    public var reps: Int? {
        guard case .repetitions(let reps) = self else { return nil }
        return reps
    }

    /// The seconds it was held, or `nil` when it was not a hold.
    public var durationSeconds: Int? {
        guard case .time(let seconds) = self else { return nil }
        return seconds
    }

    /// How far it was carried, or `nil` when it was not a carry.
    public var carried: Distance? {
        guard case .distance(let distance) = self else { return nil }
        return distance
    }

    /// Which measure this answers in, so a caller can check it against the
    /// prescription it came from rather than trusting that it matches.
    public var measure: WorkMeasure {
        switch self {
        case .repetitions: .repetitions
        case .time: .time
        case .distance(let distance):
            // The unit travels with the work, exactly as `Mass` keeps its own:
            // forty metres and forty yards are different work and nothing here
            // converts one into the other. A carry that did not happen has no
            // unit to report, and a prescribed carry is metres unless it said
            // otherwise — which is the document's word, not this type's opinion.
            .distance(distance?.unit ?? .metres)
        }
    }
}
