import Foundation
import LiftingKit

/// What a session is called.
///
/// **What it does.** Answers the one question about a stored session that is not
/// a stored string: what to put at the top of it. It states a fact and never
/// advises — what the lifter should do about a session is not decided here.
///
/// **How it is used.** `RoutineView` names each day of a block with it, and
/// `ActiveWorkoutView` the session being logged, so a row and the screen it
/// opens cannot disagree about what the workout is called.
///
/// **What it depends on.** `Weekday` from LiftingKit. No store, no view, no
/// state and no calendar.
///
/// It held three more phrasings, each printed by a screen that no longer exists:
/// a progress note for a card that was replaced by a mark, a count of exercises
/// and minutes that the day row now says by naming the movements, and a record
/// line for a block summary nothing draws. They went with what printed them.
enum TodayPhrasing {

    /// What to call this workout: what the plan said it is for, or the day
    /// the plan filed it under when it named it nothing. Both are things Claude
    /// wrote; neither is invented here.
    static func sessionTitle(focus: String, weekday: Weekday) -> String {
        focus.isEmpty ? weekday.fullName : focus
    }
}
