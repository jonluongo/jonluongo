import SwiftUI
import SwiftData

/// Decides between first-run setup and the main app, and guarantees a single
/// `UserProfile` record exists.
struct RootView: View {
    @Environment(\.modelContext) private var context
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
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { saveErrorMessage != nil }, set: { if !$0 { saveErrorMessage = nil } })
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
