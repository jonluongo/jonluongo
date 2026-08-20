import Foundation

/// A training block reduced to the only two things a calendar question needs:
/// when it started, and which weeks it prescribes.
///
/// **What it does.** Carries a block's extent as plain values, so the days it
/// covers can be worked out without a database, a simulator, or a model. It
/// states absence honestly: `startDate` is optional because a block nobody
/// dated cannot be placed on a calendar at all.
///
/// **How it is used.** The app builds one from its stored `TrainingPlan` and
/// hands it to `RoutineCalendar.span(of:)`. It is a snapshot, not a store:
/// nothing here is written back.
///
/// **It carried far more.** Every week's label, every session's weekday, focus
/// and progress, and the date the record closed the block travelled through
/// here to answer *where does today fall* — a question the app decided not to
/// ask. The week the lifter is on is the earliest still holding an unfinished
/// session, read from the record rather than derived from a date; see
/// `docs/decided.md`. What was left was a schedule whose only read fields were
/// a start date and a set of ordinals, so that is what it is.
///
/// **What it depends on.** Foundation's `Date`. Nothing else.
public struct RoutineSchedule: Hashable, Sendable {

    /// When the block's first week begins. `nil` when the block states no
    /// start date — absence, never today.
    public let startDate: Date?

    /// The ordinals of the weeks the block prescribes, in any order. The
    /// highest is what defines the extent: a plan stating weeks 1, 2 and 4
    /// covers four weeks, because the gap is a week it left rather than one to
    /// be closed up.
    public let blockOrdinals: [Int]

    public init(startDate: Date?, blockOrdinals: [Int]) {
        self.startDate = startDate
        self.blockOrdinals = blockOrdinals
    }
}
