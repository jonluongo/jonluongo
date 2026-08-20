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
    static func text(
        load: Mass?, reps: Int, durationSeconds: Int?, distance: Distance?, unit: MassUnit
    ) -> String? {
        let weight = load.map { "\($0.converted(to: unit).value.compactString) \(unit.rawValue)" }
        guard let work = work(reps: reps, durationSeconds: durationSeconds, distance: distance)
        else { return weight }
        guard let weight else { return work }
        return "\(weight) × \(work)"
    }

    /// What was performed, in its own measure. Reps first because it is what a
    /// set usually is; a hold and a carry keep their own units, which is what
    /// stops either being read as a repetition.
    private static func work(reps: Int, durationSeconds: Int?, distance: Distance?) -> String? {
        if reps > 0 { return "\(reps)" }
        if let durationSeconds, durationSeconds > 0 { return "\(durationSeconds) s" }
        // `Distance` writes itself, so a carry reads the same here as it does
        // anywhere else the record is shown.
        if let distance, distance.value > 0 { return distance.description }
        return nil
    }
}
