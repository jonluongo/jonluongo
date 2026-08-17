import SwiftUI
import SwiftData
import LiftingKit

/// Everything on record about the lifter — the Account tab.
///
/// **What it does.** Shows what Claude has been told: his goal, his experience,
/// his constraints, what he avoids, what he weighs, what he trains with, when
/// he trains, and what he can already lift. It then names, in one sentence, the
/// facts nobody has stated yet. Below that sit the things that are about the
/// app rather than about training: the unit weights are drawn in, whether the
/// rest clock runs at all, and the delete.
///
/// **The record is read-only, and shows no affordance suggesting otherwise.**
/// Claude writes these facts through the shared folder and the app displays
/// them. The two controls are the unit picker and the rest-timer switch, and
/// neither states anything about the lifter: one is how a number is drawn, the
/// other whether his phone counts down between sets. How long to rest on a
/// given exercise is not here — that is prescribed per exercise and edited on
/// the exercise.
///
/// **How it is used.** The third tab. It was Settings, which asked no training
/// question and answered none either — the record was invisible in the app, so
/// the lifter could tell Claude he weighs 185 and never see it again.
///
/// **What it depends on.** `AccountRecord` for every string it prints, the
/// `Store/` models it queries, and the shared `IconCircleRow`. It writes only
/// the display unit and the delete, exactly as before.
struct AccountView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Environment(\.exerciseCatalog) private var catalog
    /// The lifter's own clock. The only other control on this page, and the
    /// only other thing here that is his to set.
    @Environment(RestPreferences.self) private var restPreferences
    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]
    @Query(sort: \BodyMetric.date, order: .reverse) private var weighIns: [BodyMetric]
    @Query private var strengthBaselines: [StrengthBaseline]

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

    /// The master switch for the between-sets countdown. It writes to
    /// `RestPreferences`, never to the store: switching a clock off is a thing
    /// about this phone, not a fact about the lifter that Claude should read
    /// back as though he had been told it.
    private var restTimerBinding: Binding<Bool> {
        Binding(
            get: { restPreferences.timersEnabled },
            set: { restPreferences.setTimersEnabled($0) }
        )
    }

    private var facts: [LifterFactRow] {
        AccountRecord.facts(profile: profile, weighIns: weighIns, catalog: catalog)
    }

    private var baselines: [LifterFactRow] {
        AccountRecord.baselines(strengthBaselines, catalog: catalog)
    }

    /// The facts nobody has stated, as one sentence — or nothing at all, on the
    /// day the record finally holds everything it can.
    private var notYetSaid: String? {
        AccountRecord.sentence(AccountRecord.notYetSaid(
            profile: profile, weighIns: weighIns, baselineCount: strengthBaselines.count))
    }

    var body: some View {
        List {
            Section {
                if facts.isEmpty {
                    Text("Nothing yet.")
                        .font(.barbellBody)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(facts) { fact in
                        IconCircleRow(
                            systemImage: fact.systemImage, tint: .accentColor,
                            title: fact.value, subtitle: fact.label
                        )
                    }
                }
            } footer: {
                Text("Claude records these as you tell him; the app only shows them.")
            }

            if !baselines.isEmpty {
                Section("Strength") {
                    ForEach(baselines) { baseline in
                        IconCircleRow(
                            systemImage: baseline.systemImage, tint: .accentColor,
                            title: baseline.value, subtitle: baseline.label
                        )
                    }
                }
            }

            // Named rather than drawn as a row each: most of these are empty
            // for most of a record's life, and eight blank rows would be the
            // whole screen on day one. The sentence still answers what Claude
            // could know, which a page showing nothing cannot.
            if let notYetSaid {
                Section("Not yet said") {
                    Text(notYetSaid)
                        .font(.barbellBody)
                        .foregroundStyle(.secondary)
                }
            }

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

            // The second thing on this page that is the lifter's rather than
            // the record's, and it sits beside the first for that reason. A
            // lifter who does not want a countdown between sets should be able
            // to say so once, not once per exercise; how long to rest on any
            // particular one is still said on that exercise, where it means
            // something.
            Section {
                Toggle("Rest timers", isOn: restTimerBinding)
            } header: {
                Text("Rest Timer")
            } footer: {
                Text("When off, checking a set off starts no countdown. The rest Claude prescribed is still shown on every exercise — that is his plan, not a feature of the app.")
            }

            Section {
                Button(role: .destructive) {
                    showingResetConfirm = true
                } label: {
                    Text("Delete All Plans")
                }
            } footer: {
                Text("Deletes every plan and every set logged against it. Everything above is kept.")
            }
        }
        .navigationTitle("Account")
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
    /// folder and imports itself again. The footer says exactly this, and can
    /// now say it by pointing at the page: everything the delete keeps is
    /// listed above the button.
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
