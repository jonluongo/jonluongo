import Foundation
import SwiftData
import LiftingKit

/// One workout the coach prescribed, and everything performed against it.
///
/// **What it does.** Holds where a session sits — which block, and which session
/// of that block — what the coach called it, the mark he chose, and when the
/// lifter pressed Finish. Its two relationships are the seam the whole store is
/// built on: what was asked for, and what happened.
///
/// **It has no date.** *When* he trained is a fact about the record, carried by
/// `PerformedExercise.occurredAt`. A session is *session 2 of block 3*, trained
/// whenever he trains it — the app hands him the work and the calendar is not
/// its business.
///
/// **`finishedAt` is the one event field on an intent row**, kept knowingly. A
/// session can be finished with nothing ticked, so it cannot be derived from the
/// performed rows, and it is load-bearing: the merge rule treats a session as
/// trained if it was finished *or* anything was logged, which is what stops the
/// coach rewriting a session the lifter has already been through.
///
/// **What it depends on.** `SessionIcon` from LiftingKit. Read `orderedExercises`
/// rather than `plannedExercises` — SwiftData does not guarantee relationship
/// ordering, and the order work is done in is prescribed.
///
/// Every property has a default, as CloudKit requires.
@Model
final class Session {

    /// Which block this belongs to. Blocks run continuously and never restart,
    /// so this also orders the whole timeline.
    var blockOrdinal: Int = 1
    /// Which session of that block, from 1.
    var ordinal: Int = 1
    /// What the coach called it — "Push", "Upper A". Empty when he named it
    /// nothing, and the app then says where it sits rather than inventing a name.
    var focus: String = ""
    /// The mark the coach chose, by name. Empty when he chose none — which is
    /// most sessions, and draws nothing.
    ///
    /// The raw name rather than a drawn symbol: which glyph a name resolves to
    /// is the app's business and may change, while what the coach wrote must not.
    private var iconRawValue: String = ""
    /// When the lifter pressed Finish. `nil` while he has not.
    var finishedAt: Date?
    /// When the coach wrote this session — his date, not the day the phone took
    /// it in. A plan can be written long before it is imported, and reporting
    /// the arrival would be a small lie in the one place this exists to be
    /// honest about.
    var generatedAt: Date = Date()
    /// Which generation of the catalog the prescription was written against.
    var catalogVersion: Int = 0
    /// Which import this arrived in. Names the archived copy of the document.
    var sourceDocumentID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \PlannedExercise.session)
    var plannedExercises: [PlannedExercise]? = []

    /// **Nullify, not cascade, and the difference matters more here than
    /// anywhere else in the store.** A prescription is the coach's and can be
    /// rewritten; the log is what actually happened and cannot be recovered.
    /// Cascading would make deleting a session destroy the training it records.
    /// *Prescriptions are permanent* is a rule written in prose, and a delete
    /// rule is a guarantee written in the schema — this one has to point the
    /// safe way regardless. A performed row carries its own `exerciseID` and
    /// `occurredAt`, so it stays readable with no session behind it.
    @Relationship(deleteRule: .nullify, inverse: \PerformedExercise.session)
    var performedExercises: [PerformedExercise]? = []

    init(
        blockOrdinal: Int = 1, ordinal: Int = 1, focus: String = "",
        icon: SessionIcon? = nil, finishedAt: Date? = nil,
        generatedAt: Date = Date(), catalogVersion: Int = 0,
        sourceDocumentID: UUID? = nil
    ) {
        self.blockOrdinal = blockOrdinal
        self.ordinal = ordinal
        self.focus = focus
        self.iconRawValue = icon?.rawValue ?? ""
        self.finishedAt = finishedAt
        self.generatedAt = generatedAt
        self.catalogVersion = catalogVersion
        self.sourceDocumentID = sourceDocumentID
    }

    /// The mark this session carries, or `nil` when the coach chose none.
    var icon: SessionIcon? {
        get { iconRawValue.isEmpty ? nil : SessionIcon(rawValue: iconRawValue) }
        set { iconRawValue = newValue?.rawValue ?? "" }
    }

    /// Prescribed movements in the order they are to be trained.
    var orderedExercises: [PlannedExercise] {
        (plannedExercises ?? []).sorted { $0.order < $1.order }
    }

    /// Every set actually performed in this session, in the order it happened.
    var everyPerformedSet: [PerformedSet] {
        (performedExercises ?? [])
            .flatMap { $0.sets ?? [] }
            .sorted { $0.completedAt < $1.completedAt }
    }

    /// When training began: the earliest set performed, or `nil` before any.
    ///
    /// **This used to need a paragraph of defence.** Rows existed for every
    /// prescribed set from the moment the screen opened, so their presence was
    /// evidence a screen had been looked at rather than that anything was
    /// lifted, and the anchor had to be a *ticked* row. A performed row now
    /// exists only if something happened, so the earliest one is simply the
    /// earliest one.
    var startedAt: Date? { everyPerformedSet.first?.completedAt }

    /// When the last set was performed, or `nil` before any.
    var lastPerformedAt: Date? { everyPerformedSet.last?.completedAt }

    /// Whether this session has been trained, by the rule the merge uses.
    ///
    /// Finished *or* anything performed. A session the lifter finished without
    /// ticking a thing still counts: he went through it, and a plan that
    /// rewrites it would be rewriting what happened.
    var hasBeenTrained: Bool {
        finishedAt != nil || !(performedExercises ?? []).isEmpty
    }
}
