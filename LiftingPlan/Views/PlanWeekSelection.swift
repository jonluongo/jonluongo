import Foundation

/// Which week of a block the plan screen opens on, and how a week is titled.
///
/// A block may run several weeks and `PlanOverviewView` makes every one of them
/// reachable through its week picker; this only decides which one is shown
/// first, and it decides it from what has actually been logged rather than from
/// a calendar or a rule. The answer is the earliest week that still has an
/// unfinished day, so finishing the last session of week 1 moves the screen on
/// to week 2 instead of leaving it reporting a block that is done. When every
/// day in the block is finished the last week stays on screen, and a plan with
/// no weeks at all answers `nil`.
///
/// A week with no days is *not* finished: a week whose sessions have not
/// arrived is not one the lifter has completed, and the screen should stop
/// there rather than skipping past it.
///
/// Depends on: `TrainingWeek` and `WorkoutDay` from Store.
enum PlanWeekSelection {

    /// The `ordinal` of the week to show first, or `nil` when there are no weeks.
    static func currentWeekOrdinal(in weeks: [TrainingWeek]) -> Int? {
        let ordered = weeks.sorted { $0.ordinal < $1.ordinal }
        if let unfinished = ordered.first(where: { !isFinished($0) }) {
            return unfinished.ordinal
        }
        return ordered.last?.ordinal
    }

    /// Whether every session the week prescribes has been completed. A week
    /// that prescribes nothing yet has not been completed.
    static func isFinished(_ week: TrainingWeek) -> Bool {
        let days = week.orderedDays
        return !days.isEmpty && days.allSatisfy { $0.completedAt != nil }
    }

    /// `"Week 2"`, `"Week 2 · Accumulation"`, `"Week 4 · Deload"` — the week's
    /// position plus whatever the plan called it. When a plan marks a week as a
    /// deload without labelling it, that is said rather than lost.
    static func title(for week: TrainingWeek) -> String {
        var parts = ["Week \(week.ordinal)"]
        if !week.label.isEmpty {
            parts.append(week.label)
        } else if week.isDeload {
            parts.append("Deload")
        }
        return parts.joined(separator: " · ")
    }
}
