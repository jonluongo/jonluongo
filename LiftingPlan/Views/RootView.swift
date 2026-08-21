import SwiftUI
import SwiftData

/// Opens straight into the training, and carries the three failures the user
/// has to be told about.
///
/// **There is no onboarding and no profile to create.** The app asks the user
/// nothing — every training question belongs in conversation with the coach, who
/// records the answers in `ACCOUNT.md` — so the first launch shows the training,
/// empty, rather than a form. It used to insert a `UserProfile` before anything
/// could draw, because everything hung off it; nothing does now.
///
/// **There is one screen above nothing.** `BlockView` shows the whole timeline,
/// so there is no list to sit underneath it and no stack to seed. What this holds
/// instead is the alerting: a failed save, an unreadable document, and a snapshot
/// that never left the phone.
///
/// **The export failure is taken up when he arrives, not when it happens.** The
/// snapshot is written when a session is finished and when a document lands, and
/// both can happen mid-workout — where an alert about iCloud interrupts training
/// to report something he cannot act on with a barbell in his hands. The outbox
/// holds it; this reads it at the moment the app becomes his again.
///
/// **What it depends on.** `BlockView`, and the inbox and outbox from the
/// environment. It draws nothing else.
struct RootView: View {

    @Environment(\.scenePhase) private var scenePhase
    /// The inbox that takes in arriving documents. Optional so a preview need
    /// not supply one; the app always does.
    @Environment(DocumentInbox.self) private var documentInbox: DocumentInbox?
    /// The outbox that writes the snapshot out. Optional for the same reason.
    @Environment(SnapshotOutbox.self) private var snapshotOutbox: SnapshotOutbox?

    /// A failed export, taken up when the user arrives rather than the moment
    /// it happens.
    @State private var exportFailure: String?

    @Environment(RestTimerModel.self) private var restTimer

    @Query(sort: [SortDescriptor(\Session.blockOrdinal), SortDescriptor(\Session.ordinal)])
    private var sessions: [Session]

    /// **The session cover is presented here rather than from the list**, so the
    /// bar that returns to it and the screen it returns to are siblings. A cover
    /// presented one level down would sit above the bar, and the bar would have
    /// no way to raise the thing it points at.
    @State private var openSession: Session?

    /// The session underway, read off the record rather than remembered.
    private var underway: Session? { SessionProgress.underway(in: sessions) }

    var body: some View {
        NavigationStack {
            BlockView(openSession: $openSession)
        }
        // **The way back into a workout, from wherever he wandered off to.**
        // Leaving the session used to stop the clock, because the bar, the ±15
        // and the skip were all on the screen he had just left — a rest running
        // behind a screen that is gone is an alarm with nothing behind it. The
        // answer is not to end the rest, it is to keep it reachable.
        //
        // Drawn only when the cover is down: inside the session the same bar is
        // already on screen, and two would be one too many.
        .safeAreaInset(edge: .bottom) {
            if let underway, openSession == nil {
                RestTimerBar(restTimer: restTimer) { openSession = underway }
            }
        }
        .animation(.snappy, value: underway?.persistentModelID)
        .fullScreenCover(item: $openSession) { session in
            NavigationStack { ActiveWorkoutView(session: session) }
        }
        // Something that could not be read is shown rather than swallowed: an
        // unreadable document otherwise looks identical to not having been sent
        // one, and the user would wait for something that already arrived.
        .alert("Couldn't read the plan", isPresented: inboxErrorAlert) {
            Button("OK", role: .cancel) { documentInbox?.dismissError() }
        } message: {
            Text(documentInbox?.errorMessage ?? "")
        }
        // The mirror of the alert above. A snapshot that never left the phone
        // breaks the loop permanently and invisibly: the app looks fine while
        // the coach reads a record that stopped being true weeks ago.
        .alert("Couldn't share your log", isPresented: exportFailureAlert) {
            Button("OK", role: .cancel) { snapshotOutbox?.dismissError() }
        } message: {
            Text(exportFailure ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            exportFailure = snapshotOutbox?.errorMessage
        }
    }

    private var inboxErrorAlert: Binding<Bool> {
        Binding(
            get: { documentInbox?.errorMessage != nil },
            set: { if !$0 { documentInbox?.dismissError() } })
    }

    private var exportFailureAlert: Binding<Bool> {
        Binding(
            get: { exportFailure != nil },
            set: {
                if !$0 {
                    exportFailure = nil
                    snapshotOutbox?.dismissError()
                }
            })
    }
}
