import Foundation

/// How a prescribed rest is written out for the lifter.
///
/// Used by `ActiveWorkoutView`, `ExerciseLogSection` and `RestDurationSheet` so
/// one rest length reads the same everywhere. It is display only, and it offers
/// nothing: there is no list of suggested rest lengths here or anywhere else in
/// the app, because how long to rest is a training decision and the app makes
/// none. When a plan prescribes no rest, `label` answers `nil` and the caller
/// shows nothing rather than inventing a number or asking for one.
///
/// Depends on: Foundation.
enum RestPrescription {

    /// `"Rest 90s"` / `"Rest 2min 30s"`, or `nil` when no rest was prescribed.
    static func label(seconds: Int?) -> String? {
        guard let seconds else { return nil }
        return "Rest \(durationText(seconds))"
    }

    /// `"45s"`, `"2min"`, `"2min 30s"` — a duration, written the way a lifter
    /// says it.
    static func durationText(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)min" : "\(minutes)min \(remainder)s"
    }
}
