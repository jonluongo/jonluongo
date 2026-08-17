import Foundation
import LiftingKit

/// The words the front door says about a day.
///
/// **What it does.** Turns what a stored session holds — what it is for, how
/// much of it there is, how far it has got — into the short strings the Home
/// screen prints. It states facts and never advises: what the lifter should do
/// about any of them is not decided here.
///
/// **How it is used.** `TodayView` and `TodaySections` call it for every line
/// that is not a stored string. It lives apart from the views because a sentence
/// with a plural and an off-by-one in it is worth testing, and testing it
/// through a `List` would need a simulator to assert what a `String` already
/// answers.
///
/// **What it depends on.** `SessionProgress` and `Weekday` from LiftingKit. No
/// store, no view, no state, and — since the week strip went — no calendar.
enum TodayPhrasing {

    /// What to call this workout: what the plan said it is for, or the day
    /// the plan filed it under when it named it nothing. Both are things Claude
    /// wrote; neither is invented here.
    static func sessionTitle(focus: String, weekday: Weekday) -> String {
        focus.isEmpty ? weekday.fullName : focus
    }

    /// The word on the button, which names an action every time.
    ///
    /// It used to read "Open Session" on a workout already logged — a
    /// description of a screen rather than something to do, and the owner said
    /// so. Going back into a session is continuing the workout whether it was
    /// finished or abandoned mid-set, and which of the two it was is already
    /// said elsewhere; the button does not need to say it twice.
    ///
    /// A finished session still opens. It used to offer nothing at all, which
    /// left a logged day with no door: a mis-tapped Finish, a weight typed
    /// wrong, or a set done after the lifter thought he was done were all
    /// unreachable. The app is the record, and a record that cannot be
    /// corrected is not one.
    static func actionTitle(for progress: SessionProgress) -> String {
        switch progress {
        case .notStarted: "Start Workout"
        case .inProgress, .finished: "Continue Workout"
        }
    }

    /// `"5 exercises"`, and the session's length beside it when the plan stated
    /// one. Nothing is said about a session that prescribes nothing.
    static func sessionShape(exercises: Int, durationMinutes: Int?) -> String? {
        guard exercises > 0 else { return nil }
        let count = "\(exercises) exercise\(exercises == 1 ? "" : "s")"
        guard let durationMinutes else { return count }
        return "\(count) · \(durationMinutes) min"
    }

    /// `"12 of 14 sessions logged"` — what the record holds for a block that is
    /// over. A count of what happened, not a score: nothing here decides
    /// whether it was enough.
    static func recordLine(finished: Int, prescribed: Int) -> String? {
        guard prescribed > 0 else { return nil }
        return "\(finished) of \(prescribed) session\(prescribed == 1 ? "" : "s") logged"
    }
}
