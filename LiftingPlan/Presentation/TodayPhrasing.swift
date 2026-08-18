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

    /// What the card says about how far a session has got, or `nil` when it has
    /// not been touched — which is the ordinary case and says nothing.
    ///
    /// This was the word on a button: "Start Workout", "Continue Workout". The
    /// card is the button now, so there is no word to put on one — but whether
    /// he already started this session is still worth a glance, and a card that
    /// looked identical either way would lose it. It reports, and never
    /// instructs: a finished session is still open to correction, so nothing
    /// here says he is done with it.
    static func progressNote(for progress: SessionProgress) -> String? {
        switch progress {
        case .notStarted: nil
        case .inProgress: "In progress"
        case .finished: "Logged"
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
