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
/// **Three groups, because the page holds three contracts.** *What Claude knows*
/// is his record and cannot be edited here. *Preferences* are his and can.
/// *Data* is the one destructive thing. They were one undifferentiated list
/// where a toggle he owns ranked equally with a fact he cannot change and a
/// button that destroys his history — and four explanatory paragraphs were
/// threaded between them, each saying something the grouping now says for free.
///
/// **What it depends on.** `AccountRecord` for every string it prints, the
/// `Store/` models it queries, `panelRow` for the panels and `note()` for the
/// one sentence left. It writes only the display unit and the delete, exactly as
/// before.
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
                record
                preferences
                data
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.surface)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Delete all blocks?", isPresented: $showingResetConfirm, titleVisibility: .visible) {
            Button("Delete Blocks", role: .destructive) { deleteAllPlans() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The sets you logged go with them and don't come back. The block itself will import again the next time Claude's plan document arrives, without them.")
        }
        .alert("Couldn't Save", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - What Claude knows

    /// The record: the facts, the baselines folded in beside them, and the line
    /// naming what has not been said.
    ///
    /// One group rather than three, because a goal, a bench baseline and the
    /// absence of a training-day answer are all the same kind of statement —
    /// what Claude has been told, and what he has not. They were three sections
    /// with three headings, which made the page look like it held three subjects
    /// when it holds one.
    @ViewBuilder
    private var record: some View {
        let rows = facts + baselines
        Section {
            // Under the heading rather than under the panel. It states the whole
            // premise of the page — nothing here was asked by the app — so it
            // frames what follows instead of footnoting it.

            if rows.isEmpty {
                Text("Nothing yet.")
                    .font(.barbellBody)
                    .foregroundStyle(Palette.muted)
                    .panelRow(.only)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, fact in
                    LabeledContent {
                        Text(fact.value)
                            .font(.barbellSupport)
                            .foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Text(fact.label)
                            .font(.barbellSupport)
                            .foregroundStyle(Palette.muted)
                    }
                    .panelRow(.at(index, of: rows.count))
                }
            }

            // The absence of a record, drawn as a note rather than as a panel:
            // wrapping it in the same shape that holds facts would claim it is
            // one of them.
            if let notYetSaid {
                Text("Not yet said: \(notYetSaid)")
                    .note()
            }
        }
    }

    // MARK: - The lifter's own

    /// The one thing on this page he sets himself: whether his phone counts
    /// down between sets.
    ///
    /// The unit was here too, and should not have been. "Pounds or kilos" is a
    /// fact about how the lifter thinks, which is the same kind of thing as his
    /// goal and his injuries — he says it in conversation and Claude records it,
    /// through `ProfileUpdate.displayUnit`. A toggle for it was the app asking a
    /// question, which is the one thing it does not do. The note that went with
    /// it — that already-logged sets keep their unit — went too: it existed to
    /// reassure him about a switch he no longer has.
    private var preferences: some View {
        Section {
            // No heading. It read "Rest timer" above a switch labelled "Rest
            // timers" — the same word twice, one of them singular, neither
            // adding anything the other had not said.
            Toggle("Rest timers", isOn: restTimerBinding)
                .font(.barbellBody)
                .panelRow(.only)
                .listRowSeparator(.hidden)
        }
    }

    // MARK: - The one destructive thing

    /// Alone, at the bottom, and carrying no explanation of its own — the
    /// confirmation states exactly what goes and what stays, which is the moment
    /// that matters. Saying it twice made neither saying count.
    private var data: some View {
        Section {
            Button(role: .destructive) {
                showingResetConfirm = true
            } label: {
                Text("Delete All Blocks")
                    .font(.barbellBody)
            }
            .panelRow(.only)
            .listRowSeparator(.hidden)
        } header: {
            SectionHeading("Data")
        }
    }

    /// Deletes the blocks and, by cascade, every set logged against them.
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
