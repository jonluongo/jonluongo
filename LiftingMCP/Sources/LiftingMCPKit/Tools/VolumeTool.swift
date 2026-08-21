import Foundation
import LiftingKit

extension ToolRunner {

    /// Completed working sets and reps per muscle over a recent window.
    ///
    /// **It counts resistance training.** A set counts toward a muscle when the
    /// catalog classifies its exercise as resistance work; cardio and stretching
    /// do not, because this report exists to answer how much lifting a muscle
    /// has taken, and a bike ride reported as quadriceps volume or a held
    /// stretch as hamstring volume is an answer to a question nobody asked. The
    /// test of what counts is `Exercise.isResistanceTraining`, so the rule lives
    /// in one place and the report names the categories from that same list.
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
    /// **Nothing performed leaves the report.** A set that is not counted is
    /// still stated, under one of two headings that must not be confused: sets
    /// whose exercise the catalog no longer knows come back under
    /// `unattributed`, and sets whose exercise is conditioning or mobility come
    /// back under `excluded`, by category and in the units they were performed
    /// in. "The catalog cannot place this" and "this is not lifting volume" are
    /// different facts, and a reader deciding whether a user is doing too much
    /// needs both — forty minutes on a bike is absent from every number above
    /// and present in the log.
    func volumeByMuscle(_ arguments: JSONValue, in snapshot: TrainingSnapshot) -> ToolOutcome {
        let weeks = arguments["weeks"]?.intValue ?? Self.defaultVolumeWeeks
        let windowEnd = now()
        guard let windowStart = Self.calendar.date(
            byAdding: .day, value: -weeks * Self.daysPerWeek, to: windowEnd
        ) else {
            return .failure("A window of \(weeks) weeks is not a date range that exists.")
        }

        var totals: [MuscleGroup: MuscleVolume] = [:]
        var excluded = ExcludedWork()
        var unattributedSets = 0
        var unattributedIDs: Set<ExerciseID> = []

        // Every working set performed in the window. A warm-up is not volume,
        // and a performance exists only because it happened — there is no
        // completion flag to check any more.
        let performed = snapshot.performances.flatMap { performance in
            performance.workingSets
                .filter { $0.completedAt >= windowStart && $0.completedAt <= windowEnd }
                .map { (id: performance.exerciseID, set: $0) }
        }

        for record in performed {
            guard let exercise = catalog.exercise(id: record.id) else {
                unattributedSets += 1
                unattributedIDs.insert(record.id)
                continue
            }
            guard exercise.isResistanceTraining else {
                excluded.add(record.set, from: exercise)
                continue
            }
            for muscle in exercise.primaryMuscles {
                totals[muscle, default: MuscleVolume()].addPrimary(record.set)
            }
            for muscle in exercise.secondaryMuscles {
                totals[muscle, default: MuscleVolume()].addSecondary(record.set)
            }
        }

        return .report([
            "weeks": .integer(weeks),
            "windowStart": .date(windowStart),
            "windowEnd": .date(windowEnd),
            "exportedAt": .date(snapshot.exportedAt),
            "counts": .string(Self.countingRule),
            "muscles": .array(
                totals
                    .sorted {
                        $0.value.primarySets != $1.value.primarySets
                            ? $0.value.primarySets > $1.value.primarySets
                            : $0.key.rawValue < $1.key.rawValue
                    }
                    .map { $0.value.reported(as: $0.key) }),
            "excluded": excluded.reported,
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
    /// reader never has to assume. It states what is counted, what is counted
    /// elsewhere, and the one distinction a total could otherwise hide.
    static let countingRule =
        "Resistance training only: a set counts toward a muscle when the catalog classifies its "
        + "exercise as \(resistanceCategories). Cardio and stretching are real work and really "
        + "logged, but they are not lifting volume — they are reported under 'excluded', by "
        + "category, rather than counted here. Completed working sets only; warmups and "
        + "unfinished rows are excluded. Reps, seconds and distance are counted apart: a set "
        + "held for time adds to the seconds and nothing to the reps, and a set carried for "
        + "distance adds to the distance and nothing to either, so no hold and no carry is ever "
        + "reported as a repetition. Distance is a list, one total per unit, because nothing "
        + "here converts yards into metres."

    /// The categories that count, named from the same list the filter applies.
    /// Written out rather than described, so a reader is never left guessing
    /// where the line falls — and generated, so the sentence cannot drift from
    /// what is actually counted.
    static let resistanceCategories =
        ExerciseCategory.resistance.map(\.rawValue).sorted().joined(separator: ", ")

    /// How many weeks back a volume window reaches when the call does not say.
    /// A default for a report, not a prescription about a training block.
    static let defaultVolumeWeeks = 4

    /// Calendar arithmetic, not a training fact.
    static let daysPerWeek = 7

    /// Gregorian in the current time zone, so a "week back" crosses a daylight
    /// saving change the way a person's week does.
    static let calendar = Calendar(identifier: .gregorian)
}
