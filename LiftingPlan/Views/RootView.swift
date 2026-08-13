import SwiftUI
import SwiftData

/// Decides between first-run setup and the main app, and guarantees a single
/// `TrainingPreferences` record exists.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var allPreferences: [TrainingPreferences]

    var body: some View {
        Group {
            if let preferences = allPreferences.first {
                if preferences.hasCompletedSetup {
                    MainTabView(preferences: preferences)
                } else {
                    NavigationStack {
                        SetupView(preferences: preferences, isOnboarding: true)
                    }
                }
            } else {
                ProgressView("Setting up…")
                    .task { ensurePreferencesExist() }
            }
        }
    }

    private func ensurePreferencesExist() {
        guard allPreferences.isEmpty else { return }
        context.insert(TrainingPreferences())
        try? context.save()
    }
}

/// The main three-tab experience once setup is done.
struct MainTabView: View {
    let preferences: TrainingPreferences

    var body: some View {
        TabView {
            Tab("Plan", systemImage: "dumbbell.fill") {
                NavigationStack { PlanOverviewView(preferences: preferences) }
            }
            Tab("History", systemImage: "chart.line.uptrend.xyaxis") {
                NavigationStack { HistoryView() }
            }
            Tab("Settings", systemImage: "gearshape.fill") {
                NavigationStack { SettingsView(preferences: preferences) }
            }
        }
    }
}
