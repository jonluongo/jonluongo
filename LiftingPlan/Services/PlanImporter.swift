import Foundation
import SwiftData
import LiftingKit

/// Why a plan document could not be imported.
///
/// Three cases, and the first two are the same kind of thing: the document named
/// something from a vocabulary the app owns, and the app does not have it. Catch
/// it at the UI boundary and show `errorDescription` — it names the offending
/// value, which is what makes the failure fixable.
///
/// Depends on: `ExerciseID`, `SessionIcon`.
enum PlanImportError: Error, LocalizedError, Equatable {

    /// The document prescribed an exercise the catalog does not contain. The
    /// associated value is the first offending ID, in document order.
    case unknownExercise(ExerciseID)

    /// The document chose a session mark this build cannot draw. The associated
    /// value is the first offending name, in document order.
    case unknownIcon(SessionIcon)

    /// The document rewrote a session the user has already been through.
    ///
    /// It names the session rather than the block, which the old shape could not
    /// do: a plan is a flat list of sessions now, so a change to one of them does
    /// not put the rest of its block out of reach.
    case trainedSessionChanged(block: Int, ordinal: Int)

    var errorDescription: String? {
        switch self {
        case .unknownExercise(let id):
            "This plan prescribes '\(id.rawValue)', which is not in the exercise "
                + "catalog. Nothing was imported."
        case .unknownIcon(let icon):
            "This plan marks a session '\(icon.rawValue)', which is not one of the "
                + "marks this app can draw. Nothing was imported."
        case .trainedSessionChanged(let block, let ordinal):
            "This plan changes session \(ordinal) of block \(block), which has already "
                + "been trained. A set the user ticked, or a session he marked finished, "
                + "is the record of what happened and cannot be rewritten. Nothing was "
                + "imported. Send that session exactly as it stands, and the change in one "
                + "he has not reached."
        }
    }
}

/// The one place a prescription enters the store.
///
/// **What it does.** Takes a decoded `PlanDocument` and writes its sessions into
/// the store, creating what is new and rewriting what the user has not trained.
/// It records what it was handed and never clamps, floors, caps or defaults a
/// prescribed value.
///
/// **It maps the document straight into the models.** There is no intermediate
/// value type: `PlanDocument` is already a tree of plain values, and a second
/// plain-value description of the same prescription would be a third vocabulary
/// — the shape this project has paid a rewrite to remove once. `RoutineBlueprint`
/// and `DayBlueprint` were exactly that, built and read inside this file.
///
/// **This is the only producer, and no second one may be added.** The moment
/// something else can write a `PlannedSet`, the app can decide what somebody
/// should train — which is the one thing it does not do.
///
/// **What he has not done is the coach's; what he has done is the record.** A
/// session with nothing performed and no Finish is rebuilt from whatever the
/// document now says. One the user has been through is refused by ordinal,
/// with nothing taken in.
///
/// **What it depends on.** `PlanDocument` and `DocumentRefusal` from LiftingKit,
/// the catalog, and the `Store/` models.
enum PlanImporter {

    /// Where a session sits, which is its identity.
    private struct Key: Hashable {
        let block: Int
        let ordinal: Int
    }

    /// Takes the document in, or refuses it whole.
    ///
    /// Nothing is written until every check has passed: an unknown exercise, an
    /// unknown mark or a trained session being rewritten all mean nothing lands,
    /// rather than half a plan landing and the rest being reported as an error.
    static func `import`(
        _ document: PlanDocument,
        into context: ModelContext,
        catalog: any ExerciseCatalogProviding
    ) throws {
        let named = document.named(using: catalog)
        try confirmEveryExerciseExists(in: named, catalog: catalog)
        try confirmEveryIconExists(in: named)

        let stored = try context.fetch(FetchDescriptor<Session>())
        let existing = Dictionary(
            stored.map { (Key(block: $0.blockOrdinal, ordinal: $0.ordinal), $0) },
            uniquingKeysWith: { first, _ in first })

        // Refuse before writing anything, so a refusal leaves the store as it
        // was rather than partly rewritten.
        for prescribed in named.sessions {
            let key = Key(block: prescribed.blockOrdinal, ordinal: prescribed.ordinal)
            guard let session = existing[key], session.hasBeenTrained else { continue }
            guard canonical(PlanDocumentSession(reconstructing: session))
                != canonical(prescribed)
            else { continue }
            throw PlanImportError.trainedSessionChanged(
                block: prescribed.blockOrdinal, ordinal: prescribed.ordinal)
        }

        for prescribed in named.sessions {
            let key = Key(block: prescribed.blockOrdinal, ordinal: prescribed.ordinal)
            let session = existing[key] ?? {
                let fresh = Session(blockOrdinal: key.block, ordinal: key.ordinal)
                context.insert(fresh)
                return fresh
            }()
            write(prescribed, into: session, from: named, in: context)
        }

        try context.save()
    }

    /// Whether taking this document in would change anything.
    ///
    /// The inbox asks before applying, so an unchanged document arriving twice
    /// writes nothing and reports nothing. Compared through the document form,
    /// which is the same round trip the export uses.
    static func wouldChange(
        _ document: PlanDocument, in context: ModelContext,
        catalog: any ExerciseCatalogProviding
    ) throws -> Bool {
        let named = document.named(using: catalog)
        let stored = try context.fetch(FetchDescriptor<Session>())
        let existing = Dictionary(
            stored.map { (Key(block: $0.blockOrdinal, ordinal: $0.ordinal), $0) },
            uniquingKeysWith: { first, _ in first })

        return named.sessions.contains { prescribed in
            guard let session = existing[
                Key(block: prescribed.blockOrdinal, ordinal: prescribed.ordinal)]
            else { return true }
            return canonical(PlanDocumentSession(reconstructing: session))
                != canonical(prescribed)
        }
    }

    // MARK: - Writing

    /// Replaces a session's prescription with what the document states.
    ///
    /// **There are no notes to preserve here, and that is new.** The user's
    /// note used to live on the prescription, so rewriting a block meant lifting
    /// his words out and putting them back. It lives on `PerformedExercise` now
    /// — the record side — and a session that may be rewritten is by definition
    /// one he has not trained, so there is nothing of his to move.
    private static func write(
        _ prescribed: PlanDocumentSession, into session: Session,
        from document: PlanDocument, in context: ModelContext
    ) {
        session.focus = prescribed.focus
        session.icon = prescribed.icon
        session.generatedAt = document.generatedAt
        session.catalogVersion = document.catalogVersion
        session.sourceDocumentID = document.id

        for exercise in session.plannedExercises ?? [] { context.delete(exercise) }
        session.plannedExercises = []

        var order = 0
        var groupOrdinal = 0
        for entry in prescribed.entries {
            switch entry {
            case .exercise(let stated):
                let planned = make(stated, order: order, group: nil, rest: stated.restSeconds)
                planned.session = session
                context.insert(planned)
                order += 1
            case .group(let group):
                groupOrdinal += 1
                for (offset, stated) in group.exercises.enumerated() {
                    // The round's rest belongs to the last member: the clock runs
                    // after the round, not between the movements in it.
                    let isLast = offset == group.exercises.count - 1
                    let planned = make(
                        stated, order: order, group: groupOrdinal,
                        rest: isLast ? group.restSeconds : nil)
                    planned.session = session
                    context.insert(planned)
                    order += 1
                }
            }
        }
    }

    /// One prescribed exercise and every set it states.
    private static func make(
        _ stated: PlanDocumentExercise, order: Int, group: Int?, rest: Int?
    ) -> PlannedExercise {
        let planned = PlannedExercise(
            exerciseID: stated.exerciseID, order: order,
            restSeconds: rest, coachNote: stated.coachNote, groupOrdinal: group)
        planned.sets = stated.sets.enumerated().map { index, set in
            let prescribed = PlannedSet(
                setIndex: index, isWarmup: set.isWarmup, load: set.load,
                intensity: set.intensity, target: set.target)
            prescribed.exercise = planned
            return prescribed
        }
        return planned
    }

    // MARK: - Checks

    /// The form both sides of a comparison are put in before being compared.
    ///
    /// A stored session does not keep display names — the catalog owns them — so
    /// reconstructing one gives every movement an empty name while an arriving
    /// document has them filled in. Clearing both is what makes *unchanged* mean
    /// unchanged rather than *named differently*.
    private static func canonical(_ session: PlanDocumentSession) -> PlanDocumentSession {
        PlanDocumentSession(
            blockOrdinal: session.blockOrdinal, ordinal: session.ordinal,
            focus: session.focus, icon: session.icon,
            entries: session.entries.map(canonical))
    }

    private static func canonical(_ entry: PlanDocumentEntry) -> PlanDocumentEntry {
        switch entry {
        case .exercise(let exercise):
            .exercise(unnamed(exercise))
        case .group(let group):
            .group(PlanDocumentGroup(
                exercises: group.exercises.map(unnamed), restSeconds: group.restSeconds))
        }
    }

    private static func unnamed(_ exercise: PlanDocumentExercise) -> PlanDocumentExercise {
        PlanDocumentExercise(
            exerciseID: exercise.exerciseID, displayName: "",
            restSeconds: exercise.restSeconds, coachNote: exercise.coachNote,
            sets: exercise.sets)
    }

    /// Every movement must be one the catalog has.
    ///
    /// **This is the one thing the app insists on.** History is keyed by exercise
    /// identity, so a fabricated key fragments a lift's history irreparably —
    /// which is not a training decision, it is the difference between a database
    /// and a pile of text.
    private static func confirmEveryExerciseExists(
        in document: PlanDocument, catalog: any ExerciseCatalogProviding
    ) throws {
        for session in document.sessions {
            for exercise in session.exercises where catalog.exercise(id: exercise.exerciseID) == nil
            {
                throw PlanImportError.unknownExercise(exercise.exerciseID)
            }
        }
    }

    /// A mark this build cannot draw is refused by name.
    ///
    /// The app must never pick one for him: a glyph inferred from the word
    /// "Push" is the app deciding what a session trains from words it does not
    /// control. He chooses from the set the app publishes, or marks nothing.
    private static func confirmEveryIconExists(in document: PlanDocument) throws {
        for session in document.sessions {
            guard let icon = session.icon, !icon.isKnown else { continue }
            throw PlanImportError.unknownIcon(icon)
        }
    }
}
