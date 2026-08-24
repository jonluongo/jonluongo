import Foundation
import LiftingKit

/// One logged set, said in the terms it was performed in.
///
/// **What it does.** Turns what the record holds for a set — a load, and reps
/// or seconds or a distance — into the line a reader sees: `185 lb × 8`,
/// `70 lb × 40 m`, `45 s`, `8 reps`.
///
/// **Why it exists.** The exercise screen said `× \(reps)` for everything,
/// because reps was the only measure the trend carried. A carry logged as
/// seventy pounds over forty metres read `70 lb × 0`, and a plank held for
/// forty-five seconds read `0 reps` — zeroes nobody performed, printed under a
/// heading that says what he did. A set is counted, held, or carried, and the
/// line says which.
///
/// **How it is used.** `ExerciseDetailView` draws one per session. It states
/// and never converts: a distance keeps the unit it was logged in, exactly as
/// `Mass` does, because converting is a claim and this only reports.
///
/// **What it depends on.** `Mass`, `Distance` and `MassUnit` from Domain, and
/// `compactString` for the figures.
enum LoggedWorkSummary {

    /// The line for a set, or `nil` when the record holds nothing to say — a
    /// set with no load and no work against it is not a result.
    static func text(_ set: SnapshotPerformedSet) -> String? {
        let weight = set.load.map { "\($0.value.compactString) \($0.unit.rawValue)" }
        guard let work = work(set) else { return weight }
        guard let weight else { return work }
        return "\(weight) × \(work)"
    }

    /// What was performed, in its own measure.
    ///
    /// **Each measure is read as itself, and an unstated one says nothing.**
    /// `reps` used to be a non-optional `Int`, so this had to treat zero as
    /// absence — which meant a set he ticked without typing a count was
    /// indistinguishable from one he did none of, and both printed nothing. Now
    /// only a stated number prints, and a stated zero prints as zero, because
    /// somebody said it.
    private static func work(_ set: SnapshotPerformedSet) -> String? {
        // **A switch rather than a chain of guesses.** The chain read `reps`
        // first and would have shown a count for a set that also stated
        // seconds; the record can no longer say both, and this can no longer
        // pick. `Distance` writes itself, so a carry reads the same here as it
        // does anywhere else the record is shown.
        switch set.work {
        case .repetitions(let count): return count.map { "\($0)" }
        case .time(let held): return held.map { "\($0) s" }
        case .distance(let carried): return carried?.description
        case nil: return nil
        }
    }
}
