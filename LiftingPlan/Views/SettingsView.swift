import SwiftUI
import SwiftData

/// Preferences summary, on-device model status, and data management.
struct SettingsView: View {
    let preferences: TrainingPreferences

    @Environment(\.modelContext) private var context
    @Environment(PlanGenerator.self) private var generator
    @Query private var plans: [WorkoutPlan]

    @State private var showingEditSetup = false
    @State private var showingResetConfirm = false

    var body: some View {
        List {
            Section("Your setup") {
                LabeledContent("Days") {
                    Text(preferences.orderedWeekdays.map(\.shortName).joined(separator: " "))
                }
                LabeledContent("Duration", value: "\(preferences.durationMinutes) min")
                LabeledContent("Equipment", value: preferences.equipment.rawValue)
                LabeledContent("Experience", value: preferences.experience.rawValue)
                if !preferences.goal.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Goal").foregroundStyle(.secondary).font(.caption)
                        Text(preferences.goal)
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
                Text("Deletes every plan and logged set. Your day/duration/goal setup is kept.")
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingEditSetup) {
            NavigationStack {
                SetupView(preferences: preferences, isOnboarding: false)
            }
        }
        .confirmationDialog("Reset all data?", isPresented: $showingResetConfirm, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) { resetData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    private func resetData() {
        for plan in plans {
            context.delete(plan)
        }
        try? context.save()
    }
}
