import Foundation
import SwiftData
import LiftingKit

/// A group's logged sets, arranged into the rounds they were performed in.
///
/// **What it does.** Turns a group's movements — each with its own list of rows
/// — into rounds: round one is one row of every movement, round two the next.
/// Each row arrives knowing what it is called (`A1`), what the plan asked of it,
/// what was done on it last time, and which round it belongs to.
///
/// **How it is used.** `SupersetLogSection` builds one and draws it. It is a
/// value type with no view in it so the arrangement can be reasoned about and
/// tested without a screen — which is the whole of what "interleaved by round"
/// means.
///
/// **What it depends on.** `ExerciseGroup` from Services, `SetRowPrescription`
/// for what a row is shown, and `SetIdentity` for what it is called. It reads
/// the store and writes nothing, and it invents no row: a movement that has
/// fewer rows than another simply has none in the later rounds.
struct GroupRounds {

    /// One row of the table: one logged set of one movement.
    struct Row: Identifiable {
        let id: PersistentIdentifier
        let member: PlannedExercise
        let set: LoggedSet
        let identity: SetIdentity
        /// The round this row belongs to, or `nil` for a warm-up, which belongs
        /// to a movement rather than to a round.
        let round: Int?
        let prescribed: SetPrescription?
        let previousText: String
        let loadTarget: String
        let measure: WorkMeasure
    }

    /// One round: every movement's row at the same position, in group order.
    struct Round: Identifiable {
        let number: Int
        let rows: [Row]
        var id: Int { number }

        /// Whether every row of the round is ticked — which is when the rest
        /// after the round is owed, and the only moment a group's clock starts.
        var isComplete: Bool { rows.allSatisfy(\.set.isCompleted) }
    }

    /// The warm-ups, before round one, in group order. A warm-up is not part of
    /// a round: it belongs to the movement it warms up.
    let warmups: [Row]
    /// The rounds, in order.
    let rounds: [Round]
    /// What the group's work is measured in. Taken from the first movement,
    /// which is what names the shared column; a movement measured differently
    /// still logs in its own unit, because `Row.measure` is its own.
    let measure: WorkMeasure

    init(group: ExerciseGroup, plans: [TrainingPlan], unit: MassUnit) {
        let readings = group.members.map {
            SetRowPrescription(exercise: $0, plans: plans, unit: unit)
        }
        measure = readings.first?.measure ?? .repetitions

        var warmups: [Row] = []
        var working: [[Row]] = []

        for (position, member) in group.members.enumerated() {
            let reading = readings[position]
            let notation = group.notation(for: member) ?? ""
            let ordered = (member.loggedSets ?? []).sorted { $0.setIndex < $1.setIndex }

            for set in ordered where set.isWarmup {
                warmups.append(Self.row(
                    set, member: member, reading: reading, round: nil,
                    identity: .warmup(notation, exercise: member.displayName),
                    workingNumber: nil))
            }
            for (index, set) in ordered.filter({ !$0.isWarmup }).enumerated() {
                let row = Self.row(
                    set, member: member, reading: reading, round: index + 1,
                    identity: .inRound(
                        notation, exercise: member.displayName, round: index + 1),
                    workingNumber: index + 1)
                while working.count <= index { working.append([]) }
                working[index].append(row)
            }
        }

        self.warmups = warmups
        rounds = working.enumerated().map { Round(number: $0.offset + 1, rows: $0.element) }
    }

    /// Whether the round a row belongs to is finished. A warm-up belongs to no
    /// round and so never finishes one.
    func isComplete(round: Int?) -> Bool {
        guard let round else { return false }
        return rounds.first { $0.number == round }?.isComplete ?? false
    }

    private static func row(
        _ set: LoggedSet, member: PlannedExercise, reading: SetRowPrescription,
        round: Int?, identity: SetIdentity, workingNumber: Int?
    ) -> Row {
        let prescribed = workingNumber.flatMap {
            reading.prescription(forWorkingNumber: $0, isWarmup: set.isWarmup)
        }
        return Row(
            id: set.persistentModelID,
            member: member,
            set: set,
            identity: identity,
            round: round,
            prescribed: prescribed,
            previousText: reading.previousText(
                workingIndex: (workingNumber ?? 0) - 1, isWarmup: set.isWarmup),
            loadTarget: reading.loadTarget(prescribed),
            measure: reading.measure
        )
    }
}
