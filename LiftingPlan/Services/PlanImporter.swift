import Foundation
import SwiftData
import LiftingKit

/// Why a plan document could not be imported.
///
/// There is exactly one case, and that is the point: the only thing an import
/// can reject a plan for is naming an exercise the catalog does not have. Catch
/// it at the UI boundary and show `errorDescription` — it names the offending
/// ID, which is what makes the failure fixable. Depends on: `ExerciseID`.
enum PlanImportError: Error, LocalizedError, Equatable {

    /// The document prescribed an exercise the catalog does not contain. The
    /// associated value is the first offending ID, in document order.
    case unknownExercise(ExerciseID)

    var errorDescription: String? {
        switch self {
        case .unknownExercise(let id):
            "This plan prescribes '\(id.rawValue)', which is not in the exercise "
                + "catalog. Nothing was imported."
        }
    }
}

/// Brings a `PlanDocument` — a plan Claude wrote — into the store.
///
/// Call `import(_:into:catalog:)` with the app's `ModelContext` and the loaded
/// catalog; it returns the `TrainingPlan` that is now the lifter's current
/// block. This is the app's half of the loop that `SnapshotExporter` starts,
/// and the only path by which a plan enters the database.
///
/// **It does exactly one thing beyond decoding: it confirms every `ExerciseID`
/// exists in the catalog.** Not because the plan is distrusted, but because
/// training history is keyed on exercise identity — an unknown key would split
/// one lift's history into two unrelated series that can never be rejoined.
/// Nothing else is checked and nothing at all is changed: a set count is not
/// capped, an empty rep range is not filled, a rest is not clamped, a session
/// length is not floored, and a plan is never rejected for being unbalanced.
/// Whoever wrote the plan made those calls with more context than this function
/// will ever have.
///
/// An unknown ID fails the whole import with that ID named and writes nothing,
/// because a partial import that silently drops a movement is worse than a
/// clean failure — it looks like a plan.
///
/// Depends on: `PlanDocument` and `ExerciseCatalogProviding` from LiftingKit,
/// `PlanBlueprint`, and the `Store/` models.
enum PlanImporter {

    /// Imports `document`, supersedes whatever block was current, and saves.
    ///
    /// `importedAt` is when the plan arrived, which becomes the new block's
    /// start date and the moment the previous block stopped being current. It
    /// defaults to now and is injectable so tests can be explicit about order.
    ///
    /// Re-importing a document already in the store returns the existing plan
    /// untouched: nothing is inserted, nothing is superseded, and nothing that
    /// was logged against it is disturbed.
    ///
    /// Throws `PlanImportError.unknownExercise` when the document names an
    /// exercise the catalog does not have, and `PersistenceError.saveFailed`
    /// when the write fails.
    @discardableResult
    static func `import`(
        _ document: PlanDocument,
        into context: ModelContext,
        catalog: any ExerciseCatalogProviding,
        importedAt: Date = Date()
    ) throws -> TrainingPlan {
        if let alreadyImported = try plan(forDocument: document.id, in: context) {
            return alreadyImported
        }

        // Validated in full before anything is built, so a document with one
        // bad ID cannot leave a partially-mapped plan behind.
        try confirmEveryExerciseExists(in: document, using: catalog)

        let plan = PlanBlueprint(document: document).makeWorkoutPlan(
            // The document states which catalog generation its IDs were chosen
            // from, which is the honest stamp even if this build has a newer
            // one loaded.
            catalogVersion: document.catalogVersion,
            startDate: importedAt
        )
        plan.sourceDocumentID = document.id

        try supersedeOpenPlans(in: context, at: importedAt)
        context.insert(plan)
        try context.saveOrThrow()
        return plan
    }

    /// The one check. Walks the document in order so the error names the first
    /// offending ID rather than an arbitrary one.
    private static func confirmEveryExerciseExists(
        in document: PlanDocument,
        using catalog: any ExerciseCatalogProviding
    ) throws {
        for day in document.days {
            for exercise in day.exercises where catalog.exercise(id: exercise.exerciseID) == nil {
                throw PlanImportError.unknownExercise(exercise.exerciseID)
            }
        }
    }

    /// Closes every block still running, so the current block is unambiguous.
    ///
    /// An import supersedes; it never overwrites. The earlier plan, its days,
    /// its prescriptions, and every set logged against it stay exactly where
    /// they were — only the date it stopped being current is written. A block
    /// the lifter had already finished keeps its own completion date.
    private static func supersedeOpenPlans(in context: ModelContext, at date: Date) throws {
        for plan in try context.fetch(FetchDescriptor<TrainingPlan>())
        where plan.completedAt == nil {
            plan.completedAt = date
        }
    }

    /// The plan already imported from this document, if there is one.
    ///
    /// Filtered in memory rather than by predicate: a lifter has a handful of
    /// blocks, and an optional `UUID` comparison inside `#Predicate` is a
    /// subtlety this does not need to depend on.
    private static func plan(
        forDocument id: UUID,
        in context: ModelContext
    ) throws -> TrainingPlan? {
        try context.fetch(FetchDescriptor<TrainingPlan>())
            .first { $0.sourceDocumentID == id }
    }
}
