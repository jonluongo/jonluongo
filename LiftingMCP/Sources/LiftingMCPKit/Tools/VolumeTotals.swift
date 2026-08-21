import Foundation
import LiftingKit

/// Sets, reps, seconds and distance for one bucket of work.
///
/// Accumulated with `add(_:)` while `volume_by_muscle` walks the log and read
/// back once. The four numbers stay four numbers: repetitions, seconds and
/// metres are different units, and a hold or a carry added into a rep total is
/// a number nobody performed. Distance is held per unit rather than as one
/// running total, because adding yards to metres would need a conversion this
/// project does not do anywhere.
///
/// Depends on: `SnapshotPerformedSet`, `Distance` and `JSONValue`.
struct WorkTotals {
    private(set) var sets = 0
    private(set) var reps = 0
    private(set) var seconds = 0
    private(set) var distance: [DistanceUnit: Double] = [:]

    mutating func add(_ set: SnapshotPerformedSet) {
        sets += 1
        reps += set.reps ?? 0
        seconds += set.durationSeconds ?? 0
        if let carried = set.distance {
            distance[carried.unit, default: 0] += carried.value
        }
    }

    /// One total per unit, in a stable order. Empty when nothing was carried,
    /// which is an absence rather than a distance of zero.
    var reportedDistance: JSONValue {
        .array(
            distance
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { ["unit": .string($0.key.rawValue), "value": .number($0.value)] })
    }
}

/// Running totals for one muscle over a window.
///
/// Built by `volume_by_muscle` while it walks the log and read back once with
/// `reported(as:)`. Primary and secondary counts stay apart because combining
/// them would require a weighting, which is a training opinion.
///
/// Depends on: `WorkTotals`, `MuscleGroup`, `SnapshotPerformedSet` and `JSONValue`.
struct MuscleVolume {
    private var primary = WorkTotals()
    private var secondary = WorkTotals()

    /// How many sets named this muscle as a prime mover — the sort key the
    /// report orders muscles by.
    var primarySets: Int { primary.sets }

    mutating func addPrimary(_ set: SnapshotPerformedSet) { primary.add(set) }
    mutating func addSecondary(_ set: SnapshotPerformedSet) { secondary.add(set) }

    func reported(as muscle: MuscleGroup) -> JSONValue {
        [
            "muscle": .string(muscle.rawValue),
            "primarySets": .integer(primary.sets),
            "primaryReps": .integer(primary.reps),
            "primarySeconds": .integer(primary.seconds),
            "primaryDistance": primary.reportedDistance,
            "secondarySets": .integer(secondary.sets),
            "secondaryReps": .integer(secondary.reps),
            "secondarySeconds": .integer(secondary.seconds),
            "secondaryDistance": secondary.reportedDistance,
        ]
    }
}

/// The completed working sets that are not lifting volume, kept so they can be
/// stated rather than dropped.
///
/// `volume_by_muscle` hands it every set whose exercise the catalog classifies
/// as something other than resistance training, and reads it back once as
/// `excluded`. It exists because the alternative — counting those sets and
/// counting them nowhere — are both wrong: the first reports a bike ride as
/// quadriceps training, and the second tells a reader a user did nothing on a
/// day he trained for forty minutes.
///
/// It totals and names; it does not rank. Nothing here decides what an hour of
/// cycling is worth beside five sets of squats, which is a training judgement.
///
/// Depends on: `WorkTotals`, `Exercise`, `SnapshotPerformedSet` and `JSONValue`.
struct ExcludedWork {
    private var totals: [ExerciseCategory: WorkTotals] = [:]
    private var identifiers: [ExerciseCategory: Set<ExerciseID>] = [:]

    /// How many completed working sets were left out of the muscle totals.
    private(set) var sets = 0

    mutating func add(_ set: SnapshotPerformedSet, from exercise: Exercise) {
        sets += 1
        totals[exercise.category, default: WorkTotals()].add(set)
        identifiers[exercise.category, default: []].insert(exercise.id)
    }

    /// The excluded work by category, in the units it was performed in, with the
    /// exercises it was performed on named so the reader can go and look.
    var reported: JSONValue {
        [
            "sets": .integer(sets),
            "categories": .array(byCategory),
            "note": .string(note),
        ]
    }

    /// One entry per category, in a stable order.
    private var byCategory: [JSONValue] {
        totals
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { category, work in
                [
                    "category": .string(category.rawValue),
                    "sets": .integer(work.sets),
                    "reps": .integer(work.reps),
                    "seconds": .integer(work.seconds),
                    "distance": work.reportedDistance,
                    "exerciseIDs": .array(
                        (identifiers[category] ?? []).map(\.rawValue).sorted()
                            .map { .string($0) }),
                ]
            }
    }

    /// Said in words, because a number under a heading a reader skimmed past is
    /// the same as work that vanished.
    private var note: String {
        guard sets > 0 else {
            return "Every completed working set in the window was resistance training."
        }
        return "\(sets) completed working \(sets == 1 ? "set was" : "sets were") logged as "
            + "\(namedCategories), which the muscle totals above do not count — they count "
            + "resistance training only. The work happened; it is stated here in the units it "
            + "was performed in, so a user who trained is never reported as a user who did "
            + "nothing. What it is worth beside a set of squats is not this server's to say."
    }

    /// The categories present, written as a reader would say them.
    private var namedCategories: String {
        let names = totals.keys.map(\.rawValue).sorted()
        guard let last = names.last else { return "" }
        guard names.count > 1 else { return last }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
}
