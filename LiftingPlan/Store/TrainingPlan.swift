import Foundation
import SwiftData
import LiftingKit

/// A training block: a fixed-length program the lifter is working through.
///
/// This is the top of the user-data hierarchy and the unit the interface
/// treats as a project — it owns its weeks. A plan is finite by design, so
/// finishing one is a real event a future block can respond to.
///
/// **The coach's own words are part of the block.** `notes` is what he wrote
/// alongside the plan, and it is the one thing here nobody else could have
/// written. It used to be accepted by the document and dropped before it reached
/// this record, which is why it is stated as its own property rather than folded
/// into `goal`: a goal is what the block is for, a note is what he wants read.
///
/// Every property has a default or is optional, as CloudKit requires. A store
/// written before a field existed keeps every row it had and reads the new field
/// as absent, which was verified by reconstructing such a store on disk and
/// reopening it under this schema rather than by reading the code.
/// Depends on: `Weekday`.
@Model
final class TrainingPlan {
    var title: String = ""
    var goal: String = ""
    /// What the coach wrote alongside the block, in his own words. `nil` when
    /// the plan stated none. An empty string is a note he wrote empty, which is
    /// a different thing and is kept as written.
    var notes: String?
    /// When this block became the lifter's current one — which is when it
    /// arrived, not anything the plan itself decided.
    var startDate: Date = Date()
    /// When the plan was written, as its document stated. `nil` for a block that
    /// did not arrive as a document. Kept beside `startDate` rather than instead
    /// of it: a plan written on Friday and imported on Monday has two dates, and
    /// reading one for the other misdates the block.
    var generatedAt: Date?
    /// How many weeks the block runs. `nil` until a plan says.
    var weekCount: Int?
    /// When this block stopped being the lifter's current one. `nil` while it is
    /// running.
    ///
    /// **It does not mean he finished it.** Exactly one thing writes it —
    /// `PlanImporter`, closing every open block when a new plan arrives — so
    /// what it actually records is that a later block superseded this one, on
    /// this date. There is no way in the app for a lifter to declare a block
    /// finished, and until there is, reading this as completion is reading a
    /// claim nobody made: a block abandoned in week two carries the same date as
    /// one trained to the last session.
    ///
    /// What was actually done is in the weeks below it, session by session. That
    /// is the answer to "did he finish it", and it is the only one the record
    /// holds.
    var completedAt: Date?
    /// The `ExerciseCatalog.version` that produced this plan's exercise
    /// selections. A later correction to the catalog (e.g. reclassifying an
    /// exercise's muscles) can change what an already-logged set means; this
    /// stamp is what lets a future release detect a plan built against older
    /// catalog data rather than silently reinterpreting it.
    ///
    /// `nil` when nobody stamped it. It used to default to `1`, which said this
    /// block's exercises were chosen against the first catalog this app ever
    /// shipped — a claim nothing had made, and the one claim the stamp exists to
    /// prevent. `RoutineBlueprint.makeWorkoutPlan` requires the version for exactly
    /// that reason, so every block the app builds carries a real one.
    var catalogVersion: Int?
    /// Which days this block trains. Different blocks may train different days.
    /// Empty until a plan says which.
    private var weekdayRawValues: [Int] = []
    /// How long a session in this block runs. `nil` until a plan says.
    var durationMinutes: Int?
    /// The `PlanDocument.id` this block was imported from, which is what makes
    /// importing the same plan twice a no-op instead of a duplicate. `nil` for
    /// a block that did not arrive as a document.
    var sourceDocumentID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \TrainingWeek.plan)
    var weeks: [TrainingWeek]? = []

    init(
        title: String = "", goal: String = "", notes: String? = nil,
        startDate: Date = Date(), generatedAt: Date? = nil,
        weekCount: Int? = nil, weekdays: Set<Weekday> = [],
        durationMinutes: Int? = nil, catalogVersion: Int? = nil,
        sourceDocumentID: UUID? = nil
    ) {
        self.title = title
        self.goal = goal
        self.notes = notes
        self.startDate = startDate
        self.generatedAt = generatedAt
        self.weekCount = weekCount
        self.weekdayRawValues = weekdays.map(\.rawValue).sorted()
        self.durationMinutes = durationMinutes
        self.catalogVersion = catalogVersion
        self.sourceDocumentID = sourceDocumentID
    }

    var weekdays: Set<Weekday> {
        get { Set(weekdayRawValues.compactMap(Weekday.init(rawValue:))) }
        set { weekdayRawValues = newValue.map(\.rawValue).sorted() }
    }

    /// Training days in Monday-first display order.
    var orderedWeekdays: [Weekday] {
        Weekday.displayOrder.filter { weekdays.contains($0) }
    }

    /// Weeks in program order.
    var orderedWeeks: [TrainingWeek] {
        (weeks ?? []).sorted { $0.ordinal < $1.ordinal }
    }

}
