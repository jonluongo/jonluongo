import SwiftUI
import SwiftData
import LiftingKit

/// Everything on record about the lifter.
///
/// **What it does.** Shows what Claude has been told: his goal, his experience,
/// his constraints, what he avoids, what he weighs, what he trains with, when
/// he trains, and what he can already lift. It then names, in one sentence, the
/// facts nobody has stated yet. Below that sits the one thing that is about the
/// app rather than about training: the delete.
///
/// **The record is read-only, and shows no affordance suggesting otherwise.**
/// Claude writes these facts through the shared folder and the app displays
/// them. Nothing on this page is a training question, and nothing on it is a
/// preference any more: how long to rest on a given exercise is prescribed per
/// exercise and edited on the exercise.
///
/// **How it is used.** Behind the person icon on the routines list — the screen
/// it belongs to, since it is about the lifter. It was Settings, which asked no
/// training question and answered none either: the record was invisible in the
/// app, so the lifter could tell Claude he weighs 185 and never see it again.
///
/// **Two groups, because the page holds two contracts.** The record, which is
/// his and cannot be edited here, and *Data*, which is the one destructive
/// thing. There were more — a rest-timer switch, a lb/kg picker — and they are
/// gone: a single toggle silencing every countdown was the coarse version of a
/// choice that already exists per exercise, and which units he thinks in is
/// something he says to Claude like anything else. Nothing is left on a page
/// whose whole premise is that the app asks nothing.
///
/// **What it depends on.** `AccountRecord` for every string it prints, the
/// `Store/` models it queries, `panelRow` for the panels and `note()` for the
/// one sentence left. The delete is the only thing it writes.
struct AccountView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Environment(\.exerciseCatalog) private var catalog
    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]
    @Query(sort: \BodyMetric.date, order: .reverse) private var weighIns: [BodyMetric]
    @Query private var strengthBaselines: [StrengthBaseline]

    @State private var showingResetConfirm = false
    @State private var errorMessage: String?

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var facts: [StatedFact] {
        AccountRecord.facts(profile: profile, weighIns: weighIns, catalog: catalog)
    }

    private var baselines: [StatedFact] {
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
                data
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.surface)
        .navigationTitle("Account")
        // Inline, as both information sheets are. A large title here and a small
        // centred one on the two sheets beside it is the app changing what a
        // header looks like depending on which sheet you opened — the same
        // fault the root and the routine page were corrected for.
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete all routines?", isPresented: $showingResetConfirm, titleVisibility: .visible) {
            Button("Delete Routines", role: .destructive) { deleteAllPlans() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The sets you logged go with them and don't come back. The routine itself will import again the next time Claude's plan document arrives, without them.")
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
            if rows.isEmpty {
                Text("Nothing yet.")
                    .font(.supersetBody)
                    .foregroundStyle(Palette.muted)
                    .panelRow(.only)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, fact in
                    FactRow(label: fact.label, value: fact.value)
                        .panelRow(.at(index, of: rows.count))
                        .listRowSeparator(.hidden)
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

    // MARK: - The one destructive thing

    /// Alone, at the bottom, and carrying no explanation of its own — the
    /// confirmation states exactly what goes and what stays, which is the moment
    /// that matters. Saying it twice made neither saying count.
    private var data: some View {
        Section {
            SectionHeading("Data")
            Button(role: .destructive) {
                showingResetConfirm = true
            } label: {
                Text("Delete All Routines")
                    .font(.supersetBody)
            }
            .panelRow(.only)
            .listRowSeparator(.hidden)
        }
    }

    /// Deletes the routines and, by cascade, every set logged against them.
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
