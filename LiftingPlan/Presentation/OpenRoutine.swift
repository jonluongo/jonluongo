import Foundation

/// Which routine the app should have on its stack, and when it may change it
/// out from under the lifter.
///
/// **What it does.** Answers one question — given what is on the stack, which
/// routine is current, and which one the app put there itself, what should the
/// stack hold now? It decides nothing about training and reads no model; it is
/// the navigation rule written where it can be tested.
///
/// **Why it exists.** The app opens on the routine he is training, and it did
/// that once, on first appearance. A plan arriving seconds later — which is the
/// ordinary case, because the inbox reads the shared folder just after launch —
/// left him on the routine that plan had just closed: every session in it
/// logged, nothing to open, and the new block sitting behind the back arrow
/// with nothing on screen saying so.
///
/// **The lifter's own navigation is never undone.** Following `current` blindly
/// would yank a lifter out of an older block he had gone back to read. So the
/// app may replace only the routine *it* pushed, and only while that is still
/// the whole of the stack — the moment he presses back or chooses another
/// block, the stack is his and this leaves it alone.
///
/// **What it depends on.** Nothing. It is a function of three identities.
enum OpenRoutine {

    /// What the app should do with the stack.
    enum Decision<ID: Equatable>: Equatable {
        /// Leave the stack exactly as it is.
        case leave
        /// Put this routine on the stack, replacing anything the app itself put
        /// there. The caller records it as the one it opened.
        case open(ID)
    }

    /// - Parameters:
    ///   - stacked: the routines on the stack, outermost last. Empty is the
    ///     list of blocks.
    ///   - current: the routine he is training — the newest one still open.
    ///     `nil` when nothing has been sent yet.
    ///   - opened: what this rule last told the caller to open, or `nil` when it
    ///     has not opened anything this launch.
    static func decision<ID: Equatable>(
        stacked: [ID], current: ID?, opened: ID?
    ) -> Decision<ID> {
        guard let current, current != opened else { return .leave }
        // Nothing on the stack: he is on the list of blocks, either at launch or
        // having pressed back. A routine he has not been shown belongs on it.
        if stacked.isEmpty { return .open(current) }
        // Exactly what the app opened, and nothing he has done since: this is
        // the launch case, where the plan arrived after the stack was seeded.
        if stacked == [opened].compactMap({ $0 }) { return .open(current) }
        // He has navigated. The stack is his.
        return .leave
    }
}
