import Foundation
import SwiftData
import LiftingKit

/// Why a plan document could not be imported.
///
/// Two cases, and both are the same kind of thing: the document named something
/// from a vocabulary the app owns, and the app does not have it. Catch it at the
/// UI boundary and show `errorDescription` — it names the offending value, which
/// is what makes the failure fixable. Depends on: `ExerciseID`, `SessionIcon`.
enum PlanImportError: Error, LocalizedError, Equatable {

    /// The document prescribed an exercise the catalog does not contain. The
    /// associated value is the first offending ID, in document order.
    case unknownExercise(ExerciseID)

    /// The document chose a session mark this build cannot draw. The associated
    /// value is the first offending name, in document order.
    case unknownIcon(SessionIcon)

    var errorDescription: String? {
        switch self {
        case .unknownExercise(let id):
            "This plan prescribes '\(id.rawValue)', which is not in the exercise "
                + "catalog. Nothing was imported."
        case .unknownIcon(let icon):
            "This plan marks a session '\(icon.rawValue)', which is not one of the "
                + "marks this app can draw. Nothing was imported."
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
/// **It does exactly two things beyond decoding: it confirms every `ExerciseID`
/// exists in the catalog, and every session mark is one this build can draw.**
/// Not because the plan is distrusted, but because training history is keyed on
/// exercise identity — an unknown key would split one lift's history into two
/// unrelated series that can never be rejoined — and because a mark that cannot
/// be drawn would be taken in and shown as nothing, telling the writer his
/// choice landed when it did not.
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
/// **Every week the document states is imported.** A block of eight weeks
/// becomes eight `TrainingWeek`s in the order written, each with its own days,
/// its own label and its own deload flag. Nothing repeats a week to fill a
/// block out. A document whose keys this build does not know never reaches
/// here at all: it is refused while being read, with the key named — see
/// `DocumentRefusal`.
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
        try confirmEveryIconExists(in: document)

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

    /// The two checks. Both walk the document in order so the error names the
    /// first offending value rather than an arbitrary one.
    private static func confirmEveryExerciseExists(
        in document: PlanDocument,
        using catalog: any ExerciseCatalogProviding
    ) throws {
        for day in document.weeks.flatMap(\.days) {
            for exercise in day.exercises where catalog.exercise(id: exercise.exerciseID) == nil {
                throw PlanImportError.unknownExercise(exercise.exerciseID)
            }
        }
    }

    /// A mark this build cannot draw is refused by name.
    ///
    /// Taking it in and drawing nothing would tell the writer his choice landed
    /// when it did not — the same failure a silently dropped key is, and the
    /// same answer: refuse, and say which one.
    private static func confirmEveryIconExists(in document: PlanDocument) throws {
        for day in document.weeks.flatMap(\.days) {
            guard let icon = day.icon, !icon.isKnown else { continue }
            throw PlanImportError.unknownIcon(icon)
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
