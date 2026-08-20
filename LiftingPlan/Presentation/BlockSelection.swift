import Foundation

/// Which block of a routine the lifter is on, and how a block is titled.
///
/// **The record decides it, never the calendar.** The answer is the earliest
/// block that still has an unfinished session, so finishing the last session of
/// block 1 moves him on to block 2 rather than leaving the screen reporting a
/// block that is done — and a fortnight away moves him nowhere. When every
/// session is finished the last block is the answer, and a routine with no
/// blocks at all answers `nil`.
///
/// A block with no sessions is *not* finished: a block whose sessions have not
/// arrived is not one the lifter has completed, and the answer should stop
/// there rather than skipping past it.
///
/// **How it is used.** `RoutineView` locks the blocks after this one, and
/// `RoutineListing` says *Block 2 of 4* with it. The server answers the same
/// question off the snapshot in `ContextReport.currentOrdinal`, by the same
/// rule, so the phone and the coach cannot disagree about where he is.
///
/// **The stored type is `TrainingWeek` and means a block** — see the mapping in
/// `docs/decided.md`; the entity name is a CloudKit record type and stays until
/// there is a tested migration.
///
/// Depends on: `TrainingWeek` and `WorkoutDay` from Store.
enum BlockSelection {

    /// The `ordinal` of the block he is on, or `nil` when there are none.
    static func currentBlockOrdinal(in blocks: [TrainingWeek]) -> Int? {
        let ordered = blocks.sorted { $0.ordinal < $1.ordinal }
        if let unfinished = ordered.first(where: { !isFinished($0) }) {
            return unfinished.ordinal
        }
        return ordered.last?.ordinal
    }

    /// Whether every session the block prescribes has been completed. A block
    /// that prescribes nothing yet has not been completed.
    static func isFinished(_ block: TrainingWeek) -> Bool {
        let days = block.orderedDays
        return !days.isEmpty && days.allSatisfy { $0.completedAt != nil }
    }

    /// `"Block 2"`, `"Block 2 · Accumulation"`, `"Block 4 · Deload"` — its
    /// position plus whatever the plan called it. When a plan marks a block as a
    /// deload without labelling it, that is said rather than lost.
    static func title(for block: TrainingWeek) -> String {
        var parts = ["Block \(block.ordinal)"]
        if !block.label.isEmpty {
            parts.append(block.label)
        } else if block.isDeload {
            parts.append("Deload")
        }
        return parts.joined(separator: " · ")
    }
}
