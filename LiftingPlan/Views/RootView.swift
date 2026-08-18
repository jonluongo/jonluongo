import SwiftUI
import SwiftData

/// Opens straight into the app, and guarantees a single `UserProfile` record
/// exists.
///
/// **There is no onboarding.** The app asks the lifter nothing — every training
/// question belongs in conversation with Claude, who records the answers through
/// the shared folder — so the first launch shows the tabs, empty, rather than a
/// form. The profile record is still created, because everything else hangs off
/// it; it simply starts with nothing in it.
struct RootView: View {
    @Environment(\.modelContext) private var context
    /// The inbox that takes in arriving documents. Optional so a preview need
    /// not supply one; the app always does.
    @Environment(DocumentInbox.self) private var documentInbox: DocumentInbox?
    /// The outbox that writes the snapshot out. Optional for the same reason.
    @Environment(SnapshotOutbox.self) private var snapshotOutbox: SnapshotOutbox?
    @Query private var allProfiles: [UserProfile]

    @State private var saveErrorMessage: String?

    var body: some View {
        Group {
            if let profile = allProfiles.first {
                MainTabView(profile: profile)
            } else {
                // Only ever seen for the instant it takes to insert the record.
                ProgressView()
                    .task { ensureProfileExists() }
            }
        }
        // Run once a launch, before anything reads the profile: a fact an
        // earlier build recorded under a column this one renamed is carried
        // across here or it is stranded in the store forever.
        .task { upgradeStore() }
        .alert("Couldn't Save", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
        // Something that could not be read is shown rather than swallowed: an
        // unreadable document otherwise looks identical to not having been sent
        // one, and the lifter would wait for something that already arrived.
        .alert("Couldn't Read What Claude Sent", isPresented: inboxErrorAlertBinding) {
            Button("OK", role: .cancel) { documentInbox?.dismissError() }
        } message: {
            Text(documentInbox?.errorMessage ?? "")
        }
        // The mirror of the alert above, for the same reason. A snapshot that
        // never left the phone breaks the loop permanently and invisibly: the
        // app looks fine while the coach reads a document that stopped being
        // true weeks ago. The export happens as the app leaves the screen, so
        // this is shown on the next opening — the first moment there is anyone
        // to show it to.
        .alert("Couldn't Share Your Log", isPresented: exportErrorAlertBinding) {
            Button("OK", role: .cancel) { snapshotOutbox?.dismissError() }
        } message: {
            Text(snapshotOutbox?.errorMessage ?? "")
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { saveErrorMessage != nil }, set: { if !$0 { saveErrorMessage = nil } })
    }

    private var inboxErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { documentInbox?.errorMessage != nil },
            set: { if !$0 { documentInbox?.dismissError() } }
        )
    }

    private var exportErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { snapshotOutbox?.errorMessage != nil },
            set: { if !$0 { snapshotOutbox?.dismissError() } }
        )
    }

    private func ensureProfileExists() {
        guard allProfiles.isEmpty else { return }
        context.insert(UserProfile())
        save()
    }

    /// Carries anything an earlier build left in a renamed column into the shape
    /// this build reads. A failure is shown rather than swallowed: a lifter
    /// whose gym did not come across would otherwise find Claude asking him
    /// what he trains with for no reason he can see.
    private func upgradeStore() {
        do {
            try StoreUpgrade.run(in: context)
        } catch {
            saveErrorMessage = Self.describe(error)
        }
    }

    private func save() {
        do {
            try context.saveOrThrow()
        } catch {
            saveErrorMessage = Self.describe(error)
        }
    }

    private static func describe(_ error: any Error) -> String {
        (error as? PersistenceError)?.errorDescription ?? error.localizedDescription
    }
}

/// The app, which is one screen: the session he is in.
///
/// **There is no tab bar.** There were three tabs, and two of them were opened
/// roughly never — a block he has already been given and a record he cannot
/// edit — while costing ninety points of every screen he actually uses. They
/// are behind a control now, and the session has the phone.
///
/// **There is no start button and no preview.** Home used to draw today's
/// session read-only, and tapping it opened a sheet drawing the same session
/// with fields in it. That was a mode and it bought nothing: a set row with an
/// empty field *is* the preview, because the prescription is already the
/// placeholder, and the session clock starts on the first ticked set rather
/// than on a button. Opening the app puts him in the workout.
struct MainTabView: View {
    let profile: UserProfile

    var body: some View {
        TodayView(profile: profile)
    }
}
