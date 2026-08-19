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

/// The app: a block, opened where the training is.
///
/// **What it does.** Roots a stack at the list of blocks and pushes the current
/// one, so launching lands on the middle of the hierarchy — the week-by-week
/// list where a day is chosen — with the back arrow reaching the blocks behind
/// it. The session opens as a sheet from there.
///
/// **Why the middle.** The top of the tree costs a tap before every session, and
/// the bottom of it — opening straight into today's workout, which is what this
/// did — could show what was left of the week but never what was coming. The
/// middle is the only place that is one tap from training and still shows the
/// block.
struct MainTabView: View {
    let profile: UserProfile

    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]

    /// The block the app opens into: the most recent one that is not closed, and
    /// failing that the most recent there is. `nil` only when Claude has sent
    /// nothing.
    private var current: TrainingPlan? {
        plans.first { $0.completedAt == nil } ?? plans.first
    }

    /// What is on the stack. Seeded with the current block so the app opens on
    /// it, and emptied by the back arrow to reveal the list underneath.
    @State private var path: [TrainingPlan] = []

    var body: some View {
        NavigationStack(path: $path) {
            PlansView(profile: profile) { path.append($0) }
                .navigationDestination(for: TrainingPlan.self) { plan in
                    BlockView(plan: plan, profile: profile)
                }
        }
        // Only on the first appearance, and only when nothing has been chosen:
        // pushing again on every return would trap a lifter who had just pressed
        // back to look at an earlier block.
        .onAppear {
            guard path.isEmpty, let current else { return }
            path = [current]
        }
    }
}
