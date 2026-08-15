import SwiftUI
import SwiftData

/// Decides between first-run setup and the main app, and guarantees a single
/// `UserProfile` record exists.
struct RootView: View {
    @Environment(\.modelContext) private var context
    /// The inbox that imports arriving plans. Optional so a preview need not
    /// supply one; the app always does.
    @Environment(PlanInbox.self) private var planInbox: PlanInbox?
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
