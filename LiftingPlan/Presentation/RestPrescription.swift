import Foundation

/// How a prescribed rest is written out for the lifter.
///
/// **What it does.** Turns a number of seconds into the words that go in a
/// sentence: `"45 s"`, `"3 min"`, `"2 min 30 s"`.
///
/// **How it is used.** By `ExerciseRestSheet`, to say what the coach asked for
/// above the wheels that set the lifter's own clock. It is display only, and it
/// offers nothing: there is no list of suggested rest lengths here or anywhere
/// else in the app, because how long to rest is a training decision and the app
/// makes none. A plan that prescribes no rest reaches a caller that shows
/// nothing, rather than one inventing a number or asking for one.
///
/// **Spaced, because the only place it is read is inside a sentence.** It wrote
/// `"3min"`, which is fine on a label and reads as a typo in prose — and it sat
/// directly under wheels the app draws as `3 min` and `0 s`, so one screen
/// spelled one duration two ways. There is one spelling now, and it is the one
/// the wheels were already using.
///
/// **What it depends on.** Foundation.
enum RestPrescription {

    /// `"45 s"`, `"3 min"`, `"2 min 30 s"` — a duration, written the way the
    /// wheels beside it are.
    static func durationText(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds) s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes) min" : "\(minutes) min \(remainder) s"
    }
}
