import SwiftUI
import SwiftData

/// Summary of what the lifter has told us about himself, and data management.
///
/// Presented as the third tab. Reads `UserProfile` for the summary and every
/// `TrainingPlan` for the reset. Depends on: Store.
struct SettingsView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]

    @State private var showingEditSetup = false
    @State private var showingResetConfirm = false
    @State private var errorMessage: String?

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    var body: some View {
        List {
            Section("Your setup") {
                LabeledContent("Days") {
                    let days = profile.orderedPreferredWeekdays
                    Text(days.isEmpty ? "Not set yet" : days.map(\.shortName).joined(separator: " "))
                }
                LabeledContent("Duration", value: profile.preferredDurationMinutes.map { "\($0) min" } ?? "Not set yet")
                LabeledContent("Equipment", value: profile.equipmentAccess.rawValue)
                LabeledContent("Experience", value: profile.experience.rawValue)
                if !profile.goal.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Goal").foregroundStyle(.secondary).font(.caption)
                        Text(profile.goal)
                    }
                }
                Button("Edit Setup") { showingEditSetup = true }
            }

            Section {
                Button(role: .destructive) {
                    showingResetConfirm = true
                } label: {
                    Text("Reset All Data")
                }
            } footer: {
                Text("Deletes every plan and logged set. Your profile is kept.")
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingEditSetup) {
            NavigationStack {
                SetupView(profile: profile, isOnboarding: false)
            }
        }
        .confirmationDialog("Reset all data?", isPresented: $showingResetConfirm, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) { resetData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .alert("Couldn't Save", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func resetData() {
        for plan in plans {
            context.delete(plan)
        }
        do {
            try context.saveOrThrow()
        } catch {
            errorMessage = (error as? PersistenceError)?.errorDescription ?? error.localizedDescription
        }
    }
}
