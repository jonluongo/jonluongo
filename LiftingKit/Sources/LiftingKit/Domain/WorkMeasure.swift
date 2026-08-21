import Foundation

/// Which of the things a set can be measured in one prescription names.
///
/// **What it does.** Turns a target string into the single answer everything
/// downstream needs: this work is counted, or held, or carried a distance in a
/// stated unit. It is the one place the three readers are put together, and it
/// is deliberately one value rather than three booleans — `isTimed` beside
/// `isDistance` is a shape that can say *both*, and a set measured two ways is a
/// set logged wrong.
///
/// **How it is used.** The app asks it once per exercise and then binds the row
/// it draws to whichever field the answer names: `reps`, `durationSeconds`, or
/// `distance`. Because the cases are exhaustive, a build that grows a fourth
/// measure cannot compile until every place that logs one has been told what to
/// do with it — which is what stops the next measure from silently landing in
/// the rep column, the way a hold once did.
///
/// **What it depends on.** `RepRange`, `WorkDuration` and `WorkDistance`, which
/// share one unit vocabulary in `TargetUnits`. It reads and never decides: a
/// target says what it measures, and an exercise is never timed or carried
/// because of anything the user did.
///
/// A target that names nothing this build can read — `"AMRAP"`, `""`, a unit
/// nobody here has heard of — is `.repetitions`, which is what the field has
/// always been and what the prescription is still shown verbatim beside.
public enum WorkMeasure: Hashable, Sendable {

    /// Counted, in `reps`.
    case repetitions
    /// Held, in `durationSeconds`.
    case time
    /// Carried, in `distance`, over the unit it was prescribed in. The unit
    /// travels with the case because forty metres and forty yards are different
    /// work and nothing here converts one into the other.
    case distance(DistanceUnit)

    /// What this target measures. Asked in the order the readers claim text, so
    /// no target is ever read as two things.
    public init(_ text: String) {
        if WorkDuration(text).isTimed {
            self = .time
            return
        }
        if let unit = WorkDistance(text).unit {
            self = .distance(unit)
            return
        }
        self = .repetitions
    }
}
