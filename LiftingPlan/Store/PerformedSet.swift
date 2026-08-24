import Foundation
import SwiftData
import LiftingKit

/// One set the user actually did.
///
/// **A row exists only if it happened.** Nothing seeds these, so there is no
/// `isCompleted` to distinguish a row that means something from one that does
/// not. That boolean existed because a row was created for every prescribed set
/// the moment a screen opened, which also gave `reps` a default of zero — and a
/// completed working set at `185 lb × 0` is what the coach then read.
///
/// **Every measure is optional, and they never mix.** `nil` is *he did not say*;
/// a number is *he did that much*. A hold is seconds, a carry is a distance in
/// the unit it was prescribed in, and neither is ever added into a rep total —
/// that would be a number nobody performed, propagating into every report that
/// follows.
///
/// **Rest taken is not stored.** It is the gap between consecutive `completedAt`
/// timestamps, which is truer than what a timer counted: a timer that ran three
/// minutes says nothing about the minute spent talking afterwards.
///
/// **What it depends on.** `Mass` and `Distance` from LiftingKit.
///
/// Every property has a default, as CloudKit requires.
@Model
final class PerformedSet {

    /// Where this sat among the exercise's sets, from 0.
    var setIndex: Int = 0
    /// Whether this was performed as a warm-up.
    ///
    /// Stated here as well as on the prescription, and the two may honestly
    /// disagree: a user treats a prescribed working set as a warm-up often
    /// enough, and a set he added has no prescription to inherit from.
    var isWarmup: Bool = false
    /// What was on the bar. `nil` for bodyweight, and `nil` when he did not say.
    var load: Mass?
    /// The figure, in whichever column its measure uses. **Private, exactly as
    /// `PlannedSet`'s four target columns are** — read `work` instead.
    ///
    /// Three peer optionals can say *45 seconds and 8 reps*, which is a set
    /// logged two ways and therefore logged wrong. Nothing produces that any
    /// more, because `WorkDone` closed the write path — but a store that can
    /// still hold it is a store whose invariant lives in the callers, and its
    /// mirror table solved this properly. `PlannedSet` keeps four raw columns
    /// behind one typed `target`; this keeps three behind one typed `work`, and
    /// the exclusive setter is what makes the illegal state unreachable rather
    /// than merely unwritten.
    ///
    /// `nil` in all three is a set he ticked without stating a figure, which is
    /// not the same as stating none.
    private var reps: Int?
    private var durationSeconds: Int?
    /// In the unit it was prescribed in. Never converted: forty metres and
    /// forty yards are different work.
    private var distance: Distance?

    /// What the set came to, in the one measure it was performed in.
    ///
    /// **The interface; the three columns are implementation.** Setting it
    /// writes exactly one and clears the other two, so a row cannot state two
    /// measures however a caller is written.
    ///
    /// **`nil` means no figure was stated**, not that nothing happened — the
    /// row's existence is what says it happened. **This does not round-trip
    /// `.repetitions(nil)` as itself**, and that is deliberate rather than
    /// lossy: *which* measure a blank set was performed in is a fact about the
    /// prescription, which already states it, and storing it here would be the
    /// same fact in two places. A set the user added with no figure and no
    /// prescription behind it is the one case that cannot be recovered, and it
    /// carries nothing worth recovering.
    var work: WorkDone? {
        get {
            // The setter writes at most one of these, so this reads whichever
            // it wrote. The order is a formality, not a precedence rule.
            if let reps { return .repetitions(reps) }
            if let durationSeconds { return .time(seconds: durationSeconds) }
            if let distance { return .distance(distance) }
            return nil
        }
        set {
            reps = newValue?.reps
            durationSeconds = newValue?.durationSeconds
            distance = newValue?.carried
        }
    }
    /// The moment the set was recorded. Consecutive values are what rest taken
    /// is derived from.
    var completedAt: Date = Date()

    var exercise: PerformedExercise?
    /// The set this fulfils, or `nil` for one the user added and for a stated
    /// baseline.
    var planned: PlannedSet?

    init(
        setIndex: Int = 0, isWarmup: Bool = false, load: Mass? = nil,
        work: WorkDone? = nil, completedAt: Date = Date()
    ) {
        self.setIndex = setIndex
        self.isWarmup = isWarmup
        self.load = load
        self.completedAt = completedAt
        // Through the setter, so there is one place that decides which column a
        // measure lands in and it cannot be bypassed at construction.
        self.work = work
    }

    /// Whether this set counts toward progression: work rather than a warm-up.
    /// There is no completion to check — the row exists because it happened.
    var countsForProgression: Bool { !isWarmup }
}
