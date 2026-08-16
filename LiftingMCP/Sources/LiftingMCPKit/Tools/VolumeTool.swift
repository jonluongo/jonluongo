import Foundation
import LiftingKit

extension ToolRunner {

    /// Completed working sets and reps per muscle over a recent window.
    ///
    /// Primary and secondary work are counted in separate columns and never
    /// combined. Adding them would need a weighting — "a secondary set is worth
    /// half a primary one" — and that number is a training opinion, which does
    /// not belong inside a Swift function. Reported side by side, whoever is
    /// reasoning about the numbers can weigh them however they mean to.
    ///
    /// The window ends at *now*, not at the snapshot's timestamp, so a stale
    /// snapshot reports a genuinely quiet fortnight rather than pretending its
    /// last fortnight of data is the present one. `snapshotAgeDays` says how
    /// stale it is.
    ///
    /// **Every measure is reported in the unit it was performed in, never as
    /// another.** A plank logged as a 34-second hold adds 34 to `primarySeconds`
    /// and nothing at all to `primaryReps`; a farmer's carry over 40 metres adds
    /// 40 metres to `primaryDistance` and nothing to either. Counting them as
    /// reps was the error this column split exists to end — and dropping them
    /// instead would hide work that happened, so each is reported in its own
    /// unit and left to be weighed by whoever is reasoning about it.
    ///
    /// `primaryDistance` is a list rather than a number because distances carry
    /// their units: metres and yards are totalled separately and never added,
    /// since relating them would mean converting one into the other, and this
    /// server converts nothing.
    ///
    /// Sets whose exercise the catalog no longer knows cannot be attributed to
    /// a muscle; they are counted separately under `unattributed` with their
    /// IDs, rather than dropped as though the work never happened.
    func volumeByMuscle(_ arguments: JSONValue, in snapshot: TrainingSnapshot) -> ToolOutcome {
        let weeks = arguments["weeks"]?.intValue ?? Self.defaultVolumeWeeks
        let windowEnd = now()
        guard let windowStart = Self.calendar.date(
            byAdding: .day, value: -weeks * Self.daysPerWeek, to: windowEnd
        ) else {
            return .failure("A window of \(weeks) weeks is not a date range that exists.")
        }

        var totals: [MuscleGroup: MuscleVolume] = [:]
        var unattributedSets = 0
        var unattributedIDs: Set<ExerciseID> = []

        for record in TrainingLog.records(in: snapshot)
        where record.isCompletedWorkingSet
            && record.loggedSet.completedAt >= windowStart
            && record.loggedSet.completedAt <= windowEnd
        {
            guard let exercise = catalog.exercise(id: record.exercise.exerciseID) else {
                unattributedSets += 1
                unattributedIDs.insert(record.exercise.exerciseID)
                continue
            }
            for muscle in exercise.primaryMuscles {
                totals[muscle, default: MuscleVolume()].addPrimary(record.loggedSet)
            }
            for muscle in exercise.secondaryMuscles {
                totals[muscle, default: MuscleVolume()].addSecondary(record.loggedSet)
            }
        }

        return .report([
            "weeks": .integer(weeks),
            "windowStart": .date(windowStart),
            "windowEnd": .date(windowEnd),
            "snapshotGeneratedAt": .date(snapshot.generatedAt),
            "snapshotAgeDays": .integer(TrainingLog.ageInDays(of: snapshot, at: windowEnd)),
            "counts": .string(Self.countingRule),
            "muscles": .array(
                totals
                    .sorted {
                        $0.value.primarySets != $1.value.primarySets
                            ? $0.value.primarySets > $1.value.primarySets
                            : $0.key.rawValue < $1.key.rawValue
                    }
                    .map { $0.value.reported(as: $0.key) }),
            "unattributed": [
                "sets": .integer(unattributedSets),
                "exerciseIDs": .array(
                    unattributedIDs.map(\.rawValue).sorted().map { .string($0) }),
                "note": .string(
                    unattributedSets == 0
                        ? "Every logged set matched a catalog entry."
                        : "These sets were logged against IDs this catalog (version "
                            + "\(catalog.version)) does not have, so they could not be "
                            + "attributed to a muscle. The work happened; only its "
                            + "classification is unknown."),
            ],
        ])
    }

    /// What every one of these numbers counts, said in the report itself so a
    /// reader never has to assume. It states the two exclusions and the one
    /// distinction that a total could otherwise hide.
    static let countingRule =
        "Completed working sets only. Warmups and unfinished rows are excluded. Reps, seconds "
        + "and distance are counted apart: a set held for time adds to the seconds and nothing "
        + "to the reps, and a set carried for distance adds to the distance and nothing to "
        + "either, so no hold and no carry is ever reported as a repetition. Distance is a "
        + "list, one total per unit, because nothing here converts yards into metres."

    /// How many weeks back a volume window reaches when the call does not say.
    /// A default for a report, not a prescription about a training block.
    static let defaultVolumeWeeks = 4

    /// Calendar arithmetic, not a training fact.
    static let daysPerWeek = 7

    /// Gregorian in the current time zone, so a "week back" crosses a daylight
    /// saving change the way a person's week does.
    static let calendar = Calendar(identifier: .gregorian)
}

/// Running totals for one muscle over a window.
///
/// Built by `volume_by_muscle` while it walks the log and read back once with
/// `reported(as:)`. Primary and secondary counts stay apart because combining
/// them would require a weighting, which is a training opinion. Repetitions,
/// seconds and distance stay apart for a harder reason: they are different
/// units, and a hold or a carry added into a rep total is a number nobody
/// performed.
///
/// Distance is held per unit rather than as one running total, because adding
/// yards to metres would need a conversion this project does not do anywhere.
///
/// Depends on: `MuscleGroup`, `SnapshotLoggedSet`, `Distance` and `JSONValue`.
private struct MuscleVolume {
    private(set) var primarySets = 0
    private(set) var primaryReps = 0
    private(set) var primarySeconds = 0
    private(set) var primaryDistance: [DistanceUnit: Double] = [:]
    private(set) var secondarySets = 0
    private(set) var secondaryReps = 0
    private(set) var secondarySeconds = 0
    private(set) var secondaryDistance: [DistanceUnit: Double] = [:]

    mutating func addPrimary(_ set: SnapshotLoggedSet) {
        primarySets += 1
        primaryReps += set.reps
        primarySeconds += set.durationSeconds ?? 0
        if let distance = set.distance {
            primaryDistance[distance.unit, default: 0] += distance.value
        }
    }

    mutating func addSecondary(_ set: SnapshotLoggedSet) {
        secondarySets += 1
        secondaryReps += set.reps
        secondarySeconds += set.durationSeconds ?? 0
        if let distance = set.distance {
            secondaryDistance[distance.unit, default: 0] += distance.value
        }
    }

    func reported(as muscle: MuscleGroup) -> JSONValue {
        [
            "muscle": .string(muscle.rawValue),
            "primarySets": .integer(primarySets),
            "primaryReps": .integer(primaryReps),
            "primarySeconds": .integer(primarySeconds),
            "primaryDistance": Self.reported(primaryDistance),
            "secondarySets": .integer(secondarySets),
            "secondaryReps": .integer(secondaryReps),
            "secondarySeconds": .integer(secondarySeconds),
            "secondaryDistance": Self.reported(secondaryDistance),
        ]
    }

    /// One total per unit, in a stable order. Empty when nothing was carried,
    /// which is an absence rather than a distance of zero.
    private static func reported(_ totals: [DistanceUnit: Double]) -> JSONValue {
        .array(
            totals
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { ["unit": .string($0.key.rawValue), "value": .number($0.value)] })
    }
}
