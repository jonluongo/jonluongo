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
/// Reads `UserProfile` for the unit and every `TrainingPlan` for the delete.
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
                    Text("Delete All Plans")
                }
            } footer: {
                Text("Deletes every plan and every set logged against it. Your profile, your strength baselines and your body measurements are kept.")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Delete all plans?", isPresented: $showingResetConfirm, titleVisibility: .visible) {
            Button("Delete Plans", role: .destructive) { deleteAllPlans() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The sets you logged go with them and don't come back. The plan itself will import again the next time Claude's plan document arrives, without them.")
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

    /// Deletes the plans and, by cascade, every set logged against them.
    ///
    /// Deliberately nothing else. `StrengthBaseline` and `BodyMetric` are what
    /// the lifter is, not what he was asked to train — Claude records them and
    /// nothing regenerates them, whereas a plan document is still in the shared
    /// folder and imports itself again. The copy on the button says exactly
    /// this rather than promising a reset it does not perform.
    private func deleteAllPlans() {
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
