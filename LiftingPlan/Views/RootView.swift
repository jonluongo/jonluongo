import SwiftUI
import SwiftData

/// Decides between first-run setup and the main app, and guarantees a single
/// `UserProfile` record exists.
struct RootView: View {
    @Environment(\.modelContext) private var context
    /// The inbox that imports arriving plans. Optional so a preview need not
    /// supply one; the app always does.
    @Environment(PlanInbox.self) private var planInbox: PlanInbox?
    /// The outbox that writes the snapshot out. Optional for the same reason.
    @Environment(SnapshotOutbox.self) private var snapshotOutbox: SnapshotOutbox?
    @Query private var allProfiles: [UserProfile]

    @State private var saveErrorMessage: String?

    var body: some View {
        Group {
            if let profile = allProfiles.first {
                if profile.hasCompletedSetup {
                    MainTabView(profile: profile)
                } else {
                    NavigationStack {
                        SetupView(profile: profile, isOnboarding: true)
                    }
                }
            } else {
                ProgressView("Setting up…")
                    .task { ensureProfileExists() }
            }
        }
        .alert("Couldn't Save", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
        // A plan that could not be imported is shown rather than swallowed: an
        // unreadable plan otherwise looks identical to not having been sent
        // one, and the lifter would wait for something that already arrived.
        .alert("Couldn't Import Plan", isPresented: planErrorAlertBinding) {
            Button("OK", role: .cancel) { planInbox?.dismissError() }
        } message: {
            Text(planInbox?.errorMessage ?? "")
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

    private var planErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { planInbox?.errorMessage != nil },
            set: { if !$0 { planInbox?.dismissError() } }
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
        do {
            try context.saveOrThrow()
        } catch {
            saveErrorMessage = (error as? PersistenceError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// The main three-tab experience once setup is done.
struct MainTabView: View {
    let profile: UserProfile

    var body: some View {
        TabView {
            Tab("Plan", systemImage: "dumbbell.fill") {
                NavigationStack { PlanOverviewView(profile: profile) }
            }
            Tab("History", systemImage: "chart.line.uptrend.xyaxis") {
                NavigationStack { HistoryView(profile: profile) }
            }
            Tab("Settings", systemImage: "gearshape.fill") {
                NavigationStack { SettingsView(profile: profile) }
            }
        }
    }
}
