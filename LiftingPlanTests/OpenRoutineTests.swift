import Testing
@testable import LiftingPlan

/// Which routine the app opens on, and when it is allowed to change it.
///
/// The case that forced this: a plan lands a second or two after launch, which
/// is the ordinary case rather than an edge one — the inbox reads the shared
/// folder just after the first screen appears. Opening on the routine that plan
/// closed leaves a lifter looking at a block with every session logged and
/// nothing on screen saying a new one arrived.
@Suite("Which routine is open")
struct OpenRoutineTests {

    @Test("At launch, with nothing on the stack, the current routine is opened")
    func opensAtLaunch() {
        #expect(OpenRoutine.decision(stacked: [], current: "winter", opened: nil)
            == .open("winter"))
    }

    @Test("Nothing sent yet leaves the list of blocks alone")
    func nothingToOpen() {
        #expect(OpenRoutine.decision(stacked: [], current: String?.none, opened: nil)
            == .leave)
    }

    @Test("A plan arriving after launch replaces the block the app opened")
    func laterPlanReplacesWhatTheAppOpened() {
        // The whole reason this type exists: at appear the stack was seeded with
        // "winter", and the import that followed closed it and made "spring"
        // current.
        #expect(OpenRoutine.decision(stacked: ["winter"], current: "spring", opened: "winter")
            == .open("spring"))
    }

    @Test("A block he opened himself is never replaced")
    func hisOwnNavigationStands() {
        // He went back and chose an older block; the app opened nothing, so
        // there is nothing of the app's to replace.
        #expect(OpenRoutine.decision(stacked: ["autumn"], current: "spring", opened: nil)
            == .leave)
        // Or he opened one on top of what the app had opened.
        #expect(
            OpenRoutine.decision(
                stacked: ["winter", "autumn"], current: "spring", opened: "winter") == .leave)
    }

    @Test("Pressing back does not push the same routine straight back on")
    func backIsNotUndone() {
        // The stack is empty because he emptied it, and the routine he backed
        // out of is still the current one. Opening it again would trap him on it.
        #expect(OpenRoutine.decision(stacked: [], current: "winter", opened: "winter")
            == .leave)
    }

    @Test("After backing out, a routine that arrives later is still opened")
    func aNewRoutineReachesHimOnTheList() {
        #expect(OpenRoutine.decision(stacked: [], current: "spring", opened: "winter")
            == .open("spring"))
    }
}
