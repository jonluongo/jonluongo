import Foundation

/// One training block, as the coach wrote it and as the record has it since.
///
/// **What it does.** Carries the `PlanDocument` itself — the same document
/// `write_plan` produced, read back out of the store — beside the three things
/// the store knows that the document cannot: when the block was taken in, when
/// it stopped being the current one, and which of its prescribed sessions have
/// been marked finished.
///
/// **Why the document travels whole.** A prescription used to exist in three
/// vocabularies: the document coming in, the `@Model`s storing it, and a third
/// set of snapshot types reporting it back. The first and third were near-copies
/// that disagreed in shape — a document *nests* a group, the snapshot *flattened*
/// it into a marker on each member — so a superset was described twice, in two
/// encodings, with nothing but care keeping them in step. There is one
/// description now, written by the format that prescribed it, and "did my plan
/// land?" is answerable by comparison rather than by interpretation.
///
/// **The work logged against it is not here.** It is a flat series on the
/// snapshot, keyed back to this block by `document.id`. A plan is a tree written
/// once; a log is a series appended to. Bundling them meant every reader flattened
/// the tree before it could ask anything.
///
/// **How it is used.** Read `document` for what was prescribed —
/// `weeks[weekOrdinal - 1]`, the day whose `weekday` matches, its entries in
/// order. Read `sessions` for what the record says about those days.
///
/// **What it depends on.** `PlanDocument` and `Weekday`.
public struct SnapshotRoutine: Codable, Hashable, Sendable {

    /// The block as the coach wrote it.
    public let document: PlanDocument

    /// When the app took the plan in. The document states when it was *written*,
    /// which can be earlier; this is the date the block's first week begins.
    public let startDate: Date

    /// When the record says this block stopped being the current one.
    ///
    /// **Not a claim that he finished it.** The phone writes this when a later
    /// plan arrives and supersedes the block; nothing in the app lets a lifter
    /// declare one finished. A block abandoned in week two and a block trained
    /// to its last session carry the same kind of date here, and telling them
    /// apart means reading the log.
    public let completedAt: Date?

    /// What the record holds about each prescribed session. A day the plan
    /// prescribes and the record says nothing about is absent from this list
    /// rather than present with nothing in it.
    public let sessions: [SnapshotSession]

    public init(
        document: PlanDocument, startDate: Date, completedAt: Date? = nil,
        sessions: [SnapshotSession] = []
    ) {
        self.document = document
        self.startDate = startDate
        self.completedAt = completedAt
        self.sessions = sessions
    }
}

/// What the record says about one prescribed session: that the lifter marked it
/// finished, and when.
///
/// It says nothing about what was done — that is the log — and it names the
/// session by where the plan puts it rather than by an identity of its own, so
/// nothing persistent has to travel through a document.
///
/// Depends on: `Weekday`.
public struct SnapshotSession: Codable, Hashable, Sendable {

    /// 1-based position of the week within the block, matching the document's
    /// `weeks` array.
    public let weekOrdinal: Int
    public let weekday: Weekday

    /// When the lifter marked the session finished. `nil` when he has not.
    ///
    /// This is his statement and nothing else's: a session with every set
    /// ticked and no mark is unfinished, and one marked with three sets logged
    /// is finished. Only he can say which, which is what the mark is for.
    public let completedAt: Date?

    public init(weekOrdinal: Int, weekday: Weekday, completedAt: Date?) {
        self.weekOrdinal = weekOrdinal
        self.weekday = weekday
        self.completedAt = completedAt
    }
}

/// One logged set, with enough about where it sits to find what was prescribed
/// for it.
///
/// **What it does.** States what the lifter actually did on one set, and names
/// the row of the plan it answers to: the block by `routineID`, the week by
/// ordinal, the day by weekday, the movement by its position in that day, and
/// the set by its index. Follow those into `SnapshotRoutine.document` and the
/// prescription is there.
///
/// **Flat, because every question asked of it is a filter, a group or a sort.**
/// It used to be nested five deep — plan, week, day, exercise, set — and every
/// reading tool began by flattening it. This is the shape they all wanted.
///
/// **`exerciseOrder` is identity; `exerciseID` is what it is.** A day may
/// prescribe the same movement twice, so the position is what distinguishes the
/// two, while the ID is what a question about a lift filters on.
///
/// **`reps`, `durationSeconds` and `distance` are never the same number.** A set
/// is counted, held, or carried: a counted set reports reps and nothing else, a
/// hold reports the seconds it was held, and a carry reports the distance in the
/// unit it was prescribed in. Nothing sums across them.
///
/// **What it depends on.** `ExerciseID`, `Weekday`, `Mass`, `Distance`.
public struct LoggedSetRecord: Codable, Hashable, Sendable {

    /// The `PlanDocument.id` of the block this set was logged against.
    public let routineID: UUID
    /// 1-based position of the week within that block.
    public let weekOrdinal: Int
    public let weekday: Weekday
    /// Where the movement sits among the day's exercises, counting through a
    /// group's members in the order they are performed.
    public let exerciseOrder: Int
    public let exerciseID: ExerciseID
    /// Where the set sits among that movement's rows, warm-ups included.
    public let setIndex: Int
    public let isWarmup: Bool
    /// Whether the lifter ticked it. An untouched row is reported rather than
    /// dropped: a reader deciding what counts as work needs to see what was
    /// there.
    public let isCompleted: Bool
    public let completedAt: Date

    /// The load as entered, in the unit entered. `nil` when none was recorded —
    /// never zero, which would claim he lifted nothing.
    public let load: Mass?
    /// Repetitions, for a counted set. Zero for a hold or a carry.
    public let reps: Int
    /// Seconds held, for work held for time. `nil` when it was not timed, which
    /// is a different statement from a hold of no seconds.
    public let durationSeconds: Int?
    /// Distance carried, in the unit prescribed. `nil` when the carry did not
    /// happen.
    public let distance: Distance?

    public init(
        routineID: UUID, weekOrdinal: Int, weekday: Weekday, exerciseOrder: Int,
        exerciseID: ExerciseID, setIndex: Int, isWarmup: Bool, isCompleted: Bool,
        completedAt: Date, load: Mass? = nil, reps: Int = 0,
        durationSeconds: Int? = nil, distance: Distance? = nil
    ) {
        self.routineID = routineID
        self.weekOrdinal = weekOrdinal
        self.weekday = weekday
        self.exerciseOrder = exerciseOrder
        self.exerciseID = exerciseID
        self.setIndex = setIndex
        self.isWarmup = isWarmup
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.load = load
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distance = distance
    }

    /// Whether this is work rather than a warm-up or a row nobody finished. A
    /// statement about what the record says, not a judgement about whether the
    /// work was enough.
    public var isCompletedWorkingSet: Bool { isCompleted && !isWarmup }
}
