import Foundation

/// How a prescribed rest is written out for the lifter.
///
/// Used by `PrescribedExerciseRow`, `ExerciseLogSection` and `ExerciseRestSheet`
/// so one rest length reads the same everywhere. It is display only, and it
/// offers nothing: there is no list of suggested rest lengths here or anywhere
/// else in the app, because how long to rest is a training decision and the app
/// makes none. When a plan prescribes no rest, `label` answers `nil` and the
/// caller shows nothing rather than inventing a number or asking for one.
///
/// Depends on: Foundation and `LifterRest`.
enum RestPrescription {

    /// `"Rest 90s"` / `"Rest 2min 30s"`, or `nil` when no rest was prescribed.
    static func label(seconds: Int?) -> String? {
        guard let seconds else { return nil }
        return "Rest \(durationText(seconds))"
    }

    /// The line at the top of an exercise's card, which is also the control
    /// that edits its clock — or `nil` when there is nothing to say and nothing
    /// to draw.
    ///
    /// **It never lets the lifter's number stand where Claude's belongs.** The
    /// prescribed rest keeps the word `Rest` and its own figure whatever the
    /// lifter has chosen; his clock is named separately, after a dot, and only
    /// when the two differ. A lifter reading `Rest 3min · timer 2min` can see
    /// both what was asked of him and what his phone will actually run, which is
    /// the whole point: the plan is Claude's and the clock is his.
    ///
    /// With nothing prescribed there is nothing of Claude's to state, so a
    /// clock the lifter set for himself reads as `Timer 2min` and an exercise
    /// nobody has said anything about draws no line at all.
    static func line(prescribed: Int?, lifter: LifterRest, timersEnabled: Bool) -> String? {
        let running = lifter.runningSeconds(prescribed: prescribed, timersEnabled: timersEnabled)
        switch (prescribed, running) {
        case (nil, nil):
            return nil
        case (nil, let running?):
            return "Timer \(durationText(running))"
        case (let prescribed?, nil):
            return "Rest \(durationText(prescribed)) · timer off"
        case (let prescribed?, let running?):
            guard running != prescribed else { return "Rest \(durationText(prescribed))" }
            return "Rest \(durationText(prescribed)) · timer \(durationText(running))"
        }
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
