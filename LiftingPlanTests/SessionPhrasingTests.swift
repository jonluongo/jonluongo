import Testing
import Foundation
@testable import LiftingPlan
import LiftingKit

/// What a session is called.
///
/// One line, and the reason it is worth a test of its own: a session Claude
/// named nothing must still be called something, and the fallback must be his
/// data rather than the app's invention.
///
/// Four more phrasings were tested here — a week strip's day and week lines, a
/// progress note, a count of exercises and minutes, and a block's record line.
/// Each went with the screen that printed it.
@Suite("Session naming")
struct SessionPhrasingTests {

    @Test("A session is called what the plan said it is for")
    func sessionTitleUsesFocus() {
        #expect(SessionPhrasing.sessionTitle(focus: "Push", weekday: .monday) == "Push")
    }

    @Test("A session the plan named nothing is called by its day")
    func sessionTitleFallsBackToWeekday() {
        #expect(SessionPhrasing.sessionTitle(focus: "", weekday: .monday) == "Monday")
    }
}
