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
                totals[muscle, default: MuscleVolume()].addPrimary(reps: record.loggedSet.reps)
            }
            for muscle in exercise.secondaryMuscles {
                totals[muscle, default: MuscleVolume()].addSecondary(reps: record.loggedSet.reps)
            }
        }

        return .report([
            "weeks": .integer(weeks),
            "windowStart": .date(windowStart),
            "windowEnd": .date(windowEnd),
            "snapshotGeneratedAt": .date(snapshot.generatedAt),
            "snapshotAgeDays": .integer(TrainingLog.ageInDays(of: snapshot, at: windowEnd)),
            "counts": "Completed working sets only. Warmups and unfinished rows are excluded.",
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
/// them would require a weighting, which is a training opinion. Depends on:
/// `MuscleGroup` and `JSONValue`.
private struct MuscleVolume {
    private(set) var primarySets = 0
    private(set) var primaryReps = 0
    private(set) var secondarySets = 0
    private(set) var secondaryReps = 0

    mutating func addPrimary(reps: Int) {
        primarySets += 1
        primaryReps += reps
    }

    mutating func addSecondary(reps: Int) {
        secondarySets += 1
        secondaryReps += reps
    }

    func reported(as muscle: MuscleGroup) -> JSONValue {
        [
            "muscle": .string(muscle.rawValue),
            "primarySets": .integer(primarySets),
            "primaryReps": .integer(primaryReps),
            "secondarySets": .integer(secondarySets),
            "secondaryReps": .integer(secondaryReps),
        ]
    }
}
