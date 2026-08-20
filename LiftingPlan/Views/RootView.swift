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
    @Environment(\.scenePhase) private var scenePhase
    /// The inbox that takes in arriving documents. Optional so a preview need
    /// not supply one; the app always does.
    @Environment(DocumentInbox.self) private var documentInbox: DocumentInbox?
    /// The outbox that writes the snapshot out. Optional for the same reason.
    @Environment(SnapshotOutbox.self) private var snapshotOutbox: SnapshotOutbox?
    @Query private var allProfiles: [UserProfile]

    @State private var saveErrorMessage: String?
    /// A failed export, taken up when the lifter arrives rather than the moment
    /// it happens. See `exportFailureAlertBinding`.
    @State private var exportFailure: String?

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
        .alert("Couldn't Read What Arrived", isPresented: inboxErrorAlertBinding) {
            Button("OK", role: .cancel) { documentInbox?.dismissError() }
        } message: {
            Text(documentInbox?.errorMessage ?? "")
        }
        // The mirror of the alert above, for the same reason. A snapshot that
        // never left the phone breaks the loop permanently and invisibly: the
        // app looks fine while the coach reads a document that stopped being
        // true weeks ago.
        //
        // **Taken up when he arrives, not when it happens.** The snapshot is
        // written when a session is finished and when one of Claude's documents
        // lands, and both can happen while the lifter is mid-workout — where an
        // alert about iCloud interrupts training to report something he cannot
        // act on with a barbell in his hands. The outbox holds the failure; this
        // reads it at the moment the app becomes his again, which is the first
        // moment there is anyone to show it to.
        .alert("Couldn't Share Your Log", isPresented: exportFailureAlertBinding) {
            Button("OK", role: .cancel) { snapshotOutbox?.dismissError() }
        } message: {
            Text(exportFailure ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            exportFailure = snapshotOutbox?.errorMessage
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

    private var exportFailureAlertBinding: Binding<Bool> {
        Binding(
            get: { exportFailure != nil },
            set: {
                if !$0 {
                    exportFailure = nil
                    snapshotOutbox?.dismissError()
                }
            }
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
    /// The block the app put on the stack itself, as opposed to one he chose.
    /// `OpenRoutine` may replace this one and nothing else.
    @State private var opened: PersistentIdentifier?

    var body: some View {
        NavigationStack(path: $path) {
            RoutinesView(profile: profile) { path.append($0) }
                .navigationDestination(for: TrainingPlan.self) { plan in
                    RoutineView(plan: plan, profile: profile)
                }
        }
        .onAppear { follow() }
        // **A plan usually lands after the first screen has appeared.** The
        // inbox reads the shared folder just after launch, so seeding the stack
        // once on appearance opened the routine that plan then closed — every
        // session in it logged, and the new block behind the back arrow with
        // nothing saying so. `OpenRoutine` says when the app may put that right
        // and when the stack is the lifter's to keep.
        .onChange(of: current?.persistentModelID) { _, _ in follow() }
    }

    private func follow() {
        let decision = OpenRoutine.decision(
            stacked: path.map(\.persistentModelID),
            current: current?.persistentModelID, opened: opened)
        guard case .open(let identifier) = decision,
            let plan = plans.first(where: { $0.persistentModelID == identifier })
        else { return }
        opened = identifier
        path = [plan]
    }
}
