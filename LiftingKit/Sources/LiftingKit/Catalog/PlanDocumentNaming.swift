import Foundation

/// Fills in the display names a plan document left out.
///
/// **What it does.** Returns the same document with every movement's
/// `displayName` set from the catalog wherever the document stated none. An ID
/// the catalog does not have keeps whatever name it came with — refusing an
/// unknown ID is `write_plan`'s job and `PlanImporter`'s, and doing it twice
/// here would report the wrong failure.
///
/// **Why it exists.** The name is display only: it is never an identity and
/// never a join key, and the catalog that owns it is linked by the server that
/// writes plans and by the app that reads them. Asking the coach to send a
/// string both ends already hold was a key per exercise whose only possible
/// outcomes were agreeing with the catalog or disagreeing with it. He may still
/// send one — a plan written before this, or a name he has a reason for, reaches
/// the user unchanged.
///
/// **How it is used.** `write_plan` names a document before writing it, and
/// `PlanImporter` names one before taking it in — so a document that arrives
/// from anywhere is named by whoever holds the catalog, and nothing downstream
/// ever sees an unnamed movement.
///
/// **What it depends on.** `ExerciseCatalogProviding`, and the document types.
/// It changes nothing else: every other field is carried across exactly.
extension PlanDocument {

    public func named(using catalog: any ExerciseCatalogProviding) -> PlanDocument {
        PlanDocument(
            version: version, id: id, catalogVersion: catalogVersion,
            generatedAt: generatedAt,
            sessions: sessions.map { session in
                PlanDocumentSession(
                    blockOrdinal: session.blockOrdinal, ordinal: session.ordinal,
                    focus: session.focus, icon: session.icon,
                    entries: session.entries.map { $0.named(using: catalog) })
            })
    }
}

extension PlanDocumentEntry {

    fileprivate func named(using catalog: any ExerciseCatalogProviding) -> PlanDocumentEntry {
        switch self {
        case .exercise(let exercise):
            .exercise(exercise.named(using: catalog))
        case .group(let group):
            .group(PlanDocumentGroup(
                exercises: group.exercises.map { $0.named(using: catalog) },
                restSeconds: group.restSeconds))
        }
    }
}

extension PlanDocumentExercise {

    /// One initializer, so one way to rebuild. The two-branch version this
    /// replaced existed because an exercise stated its sets as either a count or
    /// a list, and naming it had to preserve which — every prescribed set is a
    /// row now, so there is nothing to preserve.
    fileprivate func named(using catalog: any ExerciseCatalogProviding) -> PlanDocumentExercise {
        guard displayName.isEmpty,
            let named = catalog.exercise(id: exerciseID)?.displayName
        else { return self }
        return PlanDocumentExercise(
            exerciseID: exerciseID, displayName: named, restSeconds: restSeconds,
            coachNote: coachNote, sets: sets)
    }
}
