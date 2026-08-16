import SwiftUI
import SwiftData
import LiftingKit

/// How the app renders weights, and data management.
///
/// Presented as the third tab. **It asks no training question.** Days, session
/// length, goal, equipment and experience are all things Claude asks better in
/// conversation and records himself, so none of them appears here — what is left
/// is the one preference that is about the app rather than about training.
///
/// Reads `UserProfile` for the unit and every `TrainingPlan` for the reset.
/// Depends on: Store.
struct SettingsView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]

    @State private var showingResetConfirm = false
    @State private var errorMessage: String?

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    /// Writes straight through to the store, so the change is saved the moment
    /// it is made rather than waiting for a Done button that does not exist.
    private var unitBinding: Binding<MassUnit> {
        Binding(get: { profile.displayUnit }, set: { setDisplayUnit($0) })
    }

    var body: some View {
        List {
            Section {
                Picker("Weight unit", selection: unitBinding) {
                    ForEach(MassUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Units")
            } footer: {
                Text("How weights are shown, and what new entries are entered in. Sets you have already logged keep the unit you logged them in.")
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

    private func setDisplayUnit(_ unit: MassUnit) {
        guard unit != profile.displayUnit else { return }
        profile.displayUnit = unit
        profile.updatedAt = Date()
        save()
    }

    private func resetData() {
        for plan in plans {
            context.delete(plan)
        }
        save()
    }

    private func save() {
        do {
            try context.saveOrThrow()
        } catch {
            errorMessage = (error as? PersistenceError)?.errorDescription ?? error.localizedDescription
        }
    }
}
