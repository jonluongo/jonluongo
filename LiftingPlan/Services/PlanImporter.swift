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

    /// The document rewrote a block the lifter has already trained. The
    /// associated value is that block's ordinal, counting from one.
    case trainedBlockChanged(Int)

    /// A block in the store has sets logged against it and the store cannot be
    /// read back as the document it came from, so there is no way to tell
    /// whether the arriving document changes it. Refused rather than guessed.
    case unreadableRoutine

    var errorDescription: String? {
        switch self {
        case .unknownExercise(let id):
            "This plan prescribes '\(id.rawValue)', which is not in the exercise "
                + "catalog. Nothing was imported."
        case .unknownIcon(let icon):
            "This plan marks a session '\(icon.rawValue)', which is not one of the "
                + "marks this app can draw. Nothing was imported."
        case .trainedBlockChanged(let ordinal):
            "This plan changes block \(ordinal), which has already been trained. Sets "
                + "logged against it are the record of what happened and cannot be "
                + "rewritten. Nothing was imported. Send the routine with block "
                + "\(ordinal) exactly as it stands and the change in a later block."
        case .unreadableRoutine:
            "This routine has training logged against it but cannot be read back as the "
                + "document it came from, so there is no way to tell what this plan "
                + "changes. Nothing was imported."
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
/// `RoutineBlueprint`, and the `Store/` models.
enum PlanImporter {

    /// Imports `document`, supersedes whatever block was current, and saves.
    ///
    /// `importedAt` is when the plan arrived, which becomes the new block's
    /// start date and the moment the previous block stopped being current. It
    /// defaults to now and is injectable so tests can be explicit about order.
    ///
    /// **A document already in the store is merged, not ignored.** That is what
    /// makes a week-at-a-time coach possible: he sends the routine again with
    /// one more block on the end, and it lands beside the blocks already there
    /// rather than becoming a second routine with the same name. A block he
    /// revised replaces the stored one; a block that vanished from the document
    /// is removed; a block already trained may not be touched at all — see
    /// `merge`.
    ///
    /// Throws `PlanImportError.unknownExercise` when the document names an
    /// exercise the catalog does not have, `PlanImportError.trainedBlockChanged`
    /// when it rewrites a block with sets logged against it, and
    /// `PersistenceError.saveFailed` when the write fails.
    @discardableResult
    static func `import`(
        _ document: PlanDocument,
        into context: ModelContext,
        catalog: any ExerciseCatalogProviding,
        importedAt: Date = Date()
    ) throws -> TrainingPlan {
        // Validated in full before anything is built, so a document with one
        // bad ID cannot leave a partially-mapped plan behind.
        try confirmEveryExerciseExists(in: document, using: catalog)
        try confirmEveryIconExists(in: document)

        // A document may leave a movement's name out — the catalog owns it, and
        // both this app and the server that writes plans link the same catalog.
        // Filled after the IDs are checked, so a wrong ID is reported as a wrong
        // ID rather than quietly acquiring a name.
        let document = document.named(using: catalog)

        if let existing = try plan(forDocument: document.id, in: context) {
            try merge(document, into: existing, in: context)
            try context.saveOrThrow()
            return existing
        }

        let plan = RoutineBlueprint(document: document).makeWorkoutPlan(
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

    /// Brings a routine already in the store up to what the document now says.
    ///
    /// **What he has not done is the coach's to change; what he has done is the
    /// record.** Jon's rule, in his words: *"the coach can change anything
    /// thats not checked off."* So a block with no completed set in it is
    /// rebuilt from the document however it now reads, a block the document no
    /// longer states is removed, and a block with any completed set is compared
    /// against what the store holds and refused by ordinal if it differs. A set
    /// he ticked is what happened; a plan that rewrites it is claiming he
    /// trained something he did not.
    ///
    /// **Unchanged is a no-op.** The same document arriving twice — which is
    /// ordinary, since the folder is re-read whenever it changes — compares
    /// equal block for block and nothing is written. That comparison is
    /// `PlanDocument(reconstructing:)`, the same round trip the export uses, so
    /// there is one answer to *what does the store say this plan was* rather
    /// than two that could drift.
    private static func merge(
        _ document: PlanDocument, into plan: TrainingPlan, in context: ModelContext
    ) throws {
        let stored = PlanDocument(reconstructing: plan)
        let blueprint = RoutineBlueprint(document: document)
        let storedWeeks = plan.orderedWeeks

        for (index, week) in storedWeeks.enumerated() where isTrained(week) {
            guard let asStored = stored?.blocks[safe: index] else {
                throw PlanImportError.unreadableRoutine
            }
            guard document.blocks[safe: index] == asStored else {
                throw PlanImportError.trainedBlockChanged(index + 1)
            }
        }

        for (index, block) in storedWeeks.enumerated() where !isTrained(block) {
            // Rebuilt rather than edited in place: a block is a tree of days,
            // exercises and prescribed sets, and reconciling one tree into
            // another field by field is where a half-applied plan comes from.
            guard document.blocks[safe: index] != stored?.blocks[safe: index] else { continue }
            // Nothing in it was logged, but something in it may still be his:
            // a note is the lifter's own words, not a prescription, and it is
            // not covered by *the coach can change anything that is not checked
            // off*. Kept across the rebuild and put back where it belongs.
            let notes = lifterNotes(in: block)
            context.delete(block)
            plan.weeks?.removeAll { $0 === block }
            if let arriving = blueprint.blocks[safe: index] {
                let rebuilt = RoutineBlueprint.makeTrainingWeek(arriving, ordinal: index + 1)
                context.insert(rebuilt)
                rebuilt.plan = plan
                restore(notes, in: rebuilt)
            }
        }

        // `stride` rather than a range: a document that states fewer blocks than
        // the store holds is ordinary — the coach dropped one — and a reversed
        // range is a crash rather than an empty loop.
        for index in stride(from: storedWeeks.count, to: blueprint.blocks.count, by: 1) {
            guard let arriving = blueprint.blocks[safe: index] else { continue }
            let added = RoutineBlueprint.makeTrainingWeek(arriving, ordinal: index + 1)
            context.insert(added)
            added.plan = plan
        }

        // A routine that grew is running again: the coach writing next week's
        // block is the plainest statement there is that the lifter is still on
        // this routine.
        if blueprint.blocks.count > storedWeeks.count { plan.completedAt = nil }
    }

    /// Where a note sits: which session of the block, which position in it, and
    /// which movement was there. All three, because a note carried to a
    /// different movement is worse than a note lost — *my elbow ached* filed
    /// under a squat he has never done is a sentence about something that never
    /// happened.
    private struct NotePlace: Hashable {
        let weekday: Weekday
        let order: Int
        let exerciseID: ExerciseID
    }

    private static func lifterNotes(in block: TrainingWeek) -> [NotePlace: String] {
        var notes: [NotePlace: String] = [:]
        for day in block.orderedDays {
            for (order, exercise) in day.orderedExercises.enumerated() {
                guard let note = exercise.lifterNote, !note.isEmpty else { continue }
                notes[NotePlace(
                    weekday: day.weekday, order: order,
                    exerciseID: exercise.exerciseID)] = note
            }
        }
        return notes
    }

    private static func restore(_ notes: [NotePlace: String], in block: TrainingWeek) {
        guard !notes.isEmpty else { return }
        for day in block.orderedDays {
            for (order, exercise) in day.orderedExercises.enumerated() {
                let place = NotePlace(
                    weekday: day.weekday, order: order, exerciseID: exercise.exerciseID)
                guard let note = notes[place] else { continue }
                exercise.lifterNote = note
            }
        }
    }

    /// Whether anything in this block is in the record. A row seeded on screen
    /// and never ticked is not — it is the app showing what was asked for, not
    /// the lifter saying he did it.
    private static func isTrained(_ block: TrainingWeek) -> Bool {
        block.orderedDays.contains { day in
            day.orderedExercises.contains { exercise in
                (exercise.loggedSets ?? []).contains { $0.isCompleted }
            }
        }
    }

    /// The two checks. Both walk the document in order so the error names the
    /// first offending value rather than an arbitrary one.
    private static func confirmEveryExerciseExists(
        in document: PlanDocument,
        using catalog: any ExerciseCatalogProviding
    ) throws {
        for day in document.blocks.flatMap(\.days) {
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
        for day in document.blocks.flatMap(\.days) {
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

    /// Whether importing this document would change anything in the store.
    ///
    /// Asked by `DocumentInbox` *before* importing, so it can tell a plan that
    /// landed from one that was merely announced again — the folder is re-read
    /// whenever it changes, and the same file arriving twice is ordinary.
    ///
    /// It was *is this identity already stored*, which stopped being the same
    /// question the day a routine could grow: next week's block arrives under
    /// the identity of the routine it belongs to, and that is a change. The
    /// answer comes from the same round trip `merge` compares with, so the two
    /// cannot disagree about what changed.
    static func wouldChange(_ document: PlanDocument, in context: ModelContext) throws -> Bool {
        guard let stored = try plan(forDocument: document.id, in: context) else { return true }
        guard let asStored = PlanDocument(reconstructing: stored) else { return true }
        return asStored.blocks != document.blocks
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

extension Array {

    /// The element at `index`, or `nil` when the array is shorter than that.
    ///
    /// The merge compares two lists of blocks that are deliberately different
    /// lengths — that is the whole point of a routine that grows — and reads
    /// them position by position. Bounds-checking each read at the call site
    /// three times over is what this replaces.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
