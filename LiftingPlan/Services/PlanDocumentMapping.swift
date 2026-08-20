import Foundation
import LiftingKit

/// Reads a stored block back into the document Claude wrote it as.
///
/// **What it does.** Turns a `TrainingPlan` and everything under it into a
/// `PlanDocument` — the same type `PlanImporter` takes in. It is the inverse of
/// the import, and it is lossless: every field the document carries is stored,
/// so a document imported and read back is the document that arrived.
///
/// **Why it exists.** A prescription currently lives in three vocabularies —
/// the document Claude writes, the `@Model`s that store it, and a third set of
/// `Snapshot*` types that report it back to him. The third is a near-copy of the
/// first that disagrees with it in shape: a document *nests* a group, the
/// snapshot *flattens* it into a marker on each member. Two encodings of one
/// fact, two mapping layers, two test suites, and one of them can drift. This is
/// what lets the snapshot carry the plan as written instead, so there is no
/// third vocabulary to keep in step.
///
/// **Reconstructed rather than kept as bytes.** Storing the original JSON on the
/// plan would also work and would be exactly faithful, but it would need a
/// column, a migration, and a second answer to "what does this block prescribe"
/// for every block imported before the column existed. The store already holds
/// every field; the round-trip test is what proves it.
///
/// **How it is used.** `PlanDocument(reconstructing:)`, and `nil` when the plan
/// carries none of the three things a document must state about itself. Those
/// are written by `PlanImporter` on every plan it takes in, so `nil` means the
/// plan did not come from a document — which nothing in this app can produce,
/// and which is exactly why it is answered with an absence rather than a
/// fabricated identity.
///
/// **What it depends on.** The `Store/` models, `SessionGrouping` for the day's
/// entries — the same reader the logging screen uses, so a group is grouped once
/// — and the document types from LiftingKit. It writes nothing.
extension PlanDocument {

    init?(reconstructing plan: TrainingPlan) {
        guard
            let id = plan.sourceDocumentID,
            let catalogVersion = plan.catalogVersion,
            let generatedAt = plan.generatedAt
        else { return nil }

        self.init(
            id: id,
            catalogVersion: catalogVersion,
            generatedAt: generatedAt,
            title: plan.title,
            goal: plan.goal,
            durationMinutes: plan.durationMinutes,
            notes: plan.notes,
            blocks: plan.orderedWeeks.map(PlanDocumentBlock.init(reconstructing:))
        )
    }
}

extension PlanDocumentBlock {

    /// A block's label is `nil` in the document and empty in the store, because
    /// SwiftData has nowhere to put an absent string. They mean the same thing:
    /// the plan did not name this block.
    init(reconstructing block: TrainingWeek) {
        self.init(
            label: block.label.isEmpty ? nil : block.label,
            isDeload: block.isDeload,
            days: block.orderedDays.map(PlanDocumentDay.init(reconstructing:))
        )
    }
}

extension PlanDocumentDay {

    /// The entries come from `SessionGrouping`, which is the one thing in the
    /// app that decides what was prescribed as a group. Reading them any other
    /// way here would be a second opinion about a fact the plan already stated.
    init(reconstructing day: WorkoutDay) {
        self.init(
            weekday: day.weekday,
            focus: day.focus,
            durationMinutes: day.durationMinutes,
            icon: day.icon,
            entries: day.entries.map(PlanDocumentEntry.init(reconstructing:))
        )
    }
}

extension PlanDocumentEntry {

    init(reconstructing entry: SessionEntry) {
        switch entry {
        case .exercise(let exercise):
            self = .exercise(PlanDocumentExercise(reconstructing: exercise))
        case .group(let group):
            // **The rest comes off the members and onto the group.** The format
            // refuses a rest inside a group — the rest is taken after the round,
            // so a rest on a member is a rest nobody takes — and the import
            // writes the group's onto the member the round ends with. This puts
            // it back where it was written.
            self = .group(PlanDocumentGroup(
                exercises: group.members.map {
                    PlanDocumentExercise(reconstructing: $0, restingWithTheRound: true)
                },
                restSeconds: group.restSeconds
            ))
        }
    }
}

extension PlanDocumentExercise {

    /// One movement, with its sets stated the way the plan stated them: as a
    /// count when it prescribed the same work throughout, and one at a time when
    /// it listed them.
    ///
    /// `restingWithTheRound` is for a member of a group, whose rest belongs to
    /// the group rather than to it.
    init(reconstructing exercise: PlannedExercise, restingWithTheRound: Bool = false) {
        let stated = exercise.orderedStatedSets.map(\.prescription)
        let rest = restingWithTheRound ? nil : exercise.restSeconds
        if stated.isEmpty {
            self.init(
                exerciseID: exercise.exerciseID,
                displayName: exercise.displayName,
                sets: exercise.targetSets,
                repRange: exercise.repRange,
                restSeconds: rest,
                suggestedLoad: exercise.suggestedLoad,
                intensity: exercise.intensity,
                tempo: exercise.tempo,
                notes: exercise.notes
            )
        } else {
            self.init(
                exerciseID: exercise.exerciseID,
                displayName: exercise.displayName,
                sets: stated,
                repRange: exercise.repRange,
                restSeconds: rest,
                suggestedLoad: exercise.suggestedLoad,
                intensity: exercise.intensity,
                tempo: exercise.tempo,
                notes: exercise.notes
            )
        }
    }
}
