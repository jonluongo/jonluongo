import Foundation
import LiftingKit

/// Reads a stored session back into the document the coach wrote it as.
///
/// **What it does.** Turns `Session` and everything under it into a
/// `PlanDocumentSession`, entry for entry and set for set, so the snapshot can
/// carry the prescription itself rather than a second description of it.
///
/// **Why it exists.** A prescription used to live in three vocabularies — the
/// document, the models, and a tree of snapshot types — and the first and third
/// disagreed about how a superset is written. There are two now, and this is the
/// bridge. The round-trip suite is what says the store holds everything the
/// document stated. Do not add a third: a type that restates a prescription for
/// a reader is the shape this cost a rewrite to remove.
///
/// **What it depends on.** `PlanDocumentSession` and its children from
/// LiftingKit, and the `Store/` models. It decides nothing and fills nothing in:
/// an unstated rest stays unstated, and an unstated target stays `nil`.
extension PlanDocumentSession {

    /// The document form of one stored session.
    init(reconstructing session: Session) {
        self.init(
            blockOrdinal: session.blockOrdinal,
            ordinal: session.ordinal,
            focus: session.focus,
            icon: session.icon,
            entries: Self.entries(of: session))
    }

    /// A session's exercises, regrouped into the entries they were written as.
    ///
    /// Members of one group are contiguous by construction, so a run of
    /// exercises sharing a `groupOrdinal` is one entry and everything else is
    /// its own.
    private static func entries(of session: Session) -> [PlanDocumentEntry] {
        var entries: [PlanDocumentEntry] = []
        var pending: [PlannedExercise] = []

        func flush() {
            guard !pending.isEmpty else { return }
            entries.append(Self.entry(for: pending))
            pending = []
        }

        for exercise in session.orderedExercises {
            guard let group = exercise.groupOrdinal else {
                flush()
                entries.append(.exercise(PlanDocumentExercise(reconstructing: exercise)))
                continue
            }
            if pending.first?.groupOrdinal != group { flush() }
            pending.append(exercise)
        }
        flush()
        return entries
    }

    /// One run of grouped exercises as the entry it was written as.
    ///
    /// **The round's rest is read off the last member.** The store holds the
    /// flattened form — nothing after the early members, the round's rest after
    /// the last — because that is what the clock has to run. The document states
    /// it once, and a member cannot state its own: `DocumentRefusal.restInsideGroup`
    /// refuses that, since a rest on one member alone is a rest nobody takes.
    ///
    /// A group of one cannot be written — the format refuses it — so a lone
    /// member of a group is reconstructed as the plain exercise it effectively is.
    private static func entry(for members: [PlannedExercise]) -> PlanDocumentEntry {
        let exercises = members.map(PlanDocumentExercise.init(reconstructingGroupMember:))
        guard members.count > 1 else {
            return .exercise(PlanDocumentExercise(reconstructing: members[0]))
        }
        return .group(PlanDocumentGroup(
            exercises: exercises, restSeconds: members.last?.restSeconds))
    }
}

extension PlanDocumentExercise {

    /// One stored exercise as the document wrote it.
    init(reconstructing exercise: PlannedExercise) {
        self.init(
            exerciseID: exercise.exerciseID,
            displayName: "",
            restSeconds: exercise.restSeconds,
            coachNote: exercise.coachNote,
            sets: exercise.orderedSets.map(PlanDocumentSet.init(reconstructing:)))
    }

    /// A member of a group, whose rest belongs to the group rather than to it.
    fileprivate init(reconstructingGroupMember exercise: PlannedExercise) {
        self.init(
            exerciseID: exercise.exerciseID,
            displayName: "",
            restSeconds: nil,
            coachNote: exercise.coachNote,
            sets: exercise.orderedSets.map(PlanDocumentSet.init(reconstructing:)))
    }
}

extension PlanDocumentSet {

    /// One stored set as the document wrote it.
    init(reconstructing set: PlannedSet) {
        self.init(
            target: set.target,
            load: set.load,
            intensity: set.intensity,
            isWarmup: set.isWarmup)
    }
}
