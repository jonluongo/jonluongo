import SwiftUI
import SwiftData

/// Preferences summary, on-device model status, and data management.
struct SettingsView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Environment(PlanGenerator.self) private var generator
    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]

    @State private var showingEditSetup = false
    @State private var showingResetConfirm = false
    @State private var errorMessage: String?

    private var currentPlan: TrainingPlan? { plans.first }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    var body: some View {
        List {
            Section("Your setup") {
                LabeledContent("Days") {
                    Text(currentPlan.map { $0.orderedWeekdays.map(\.shortName).joined(separator: " ") } ?? "Not set yet")
                }
                LabeledContent("Duration", value: currentPlan.map { "\($0.durationMinutes) min" } ?? "—")
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
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: generator.availability.isAvailable ? "sparkles" : "square.grid.2x2")
                        .foregroundStyle(generator.availability.isAvailable ? .orange : .secondary)
                    Text(generator.availability.statusMessage)
                        .font(.footnote)
                }
                .padding(.vertical, 2)
            } header: {
                Text("Plan engine")
            } footer: {
                Text("Plans are generated privately on your device. When Apple Intelligence isn't available, built-in templates are used so everything still works.")
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
