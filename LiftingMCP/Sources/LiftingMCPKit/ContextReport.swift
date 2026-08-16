import Foundation
import LiftingKit

/// The compact context that rides along on every turn: who the lifter is, what
/// he has to train with, what block he is on, what he did lately, and what he
/// is currently working with on each lift.
///
/// Built by `ToolRunner.contextResource()` and served as the one MCP resource.
/// It is deliberately small — small enough to carry constantly — which is what
/// makes the drill-down tools worth having: depth is paid for only when it is
/// wanted, and `note` says where to go for it.
///
/// Everything here is a restatement of the snapshot. It concludes nothing: no
/// readiness score, no assessment of whether a lift is stalling, no verdict on
/// balance. Those are Claude's to draw from the data.
///
/// Depends on: `ToolRunner`, `TrainingLog`, and the snapshot value types.
struct ContextReport {
    let runner: ToolRunner
    let snapshot: TrainingSnapshot

    /// How many recent sessions ride along before the tools take over.
    static let carriedSessions = 5

    func build() -> JSONValue {
        [
            "snapshotGeneratedAt": .date(snapshot.generatedAt),
            "snapshotAgeDays": .integer(TrainingLog.ageInDays(of: snapshot, at: runner.now())),
            "catalogVersion": .integer(snapshot.catalogVersion),
            "lifter": lifter,
            "currentBlock": currentBlock,
            "recentSessions": recentSessions,
            "workingWeights": workingWeights,
            "note": .string(note),
        ]
    }

    // MARK: - Who he is

    /// Who he is, with the facts nobody has stated left as `null`.
    ///
    /// A `null` here means he has not said, not that the answer is nothing.
    /// The app asks him nothing, so an unfilled field is the ordinary state of
    /// a lifter early in a conversation — and reporting a plausible default
    /// instead would be this server asserting something about him that nobody
    /// ever said.
    private var lifter: JSONValue {
        guard let profile = snapshot.profile else { return .null }
        return [
            "experience": .string(profile.experience?.rawValue),
            "goal": .string(profile.goal),
            "constraints": .string(profile.constraints),
            "availableEquipment": profile.availableEquipment.map { .taxonomy($0) } ?? .null,
            "avoidedPatterns": .taxonomy(profile.avoidedPatterns),
            "avoidedExercises": .array(profile.avoidedExercises.map { .string($0.rawValue) }),
            "preferredWeekdays": .array(profile.preferredWeekdays.map { .string($0.fullName) }),
            "preferredDurationMinutes": .integer(profile.preferredDurationMinutes),
            "displayUnit": .string(profile.displayUnit.rawValue),
            "bodyweight": .mass(LifterFacts.latestBodyweight(in: snapshot)),
            "unstated": .array(unstatedFacts.map { .string($0) }),
        ]
    }

    /// The facts nobody has stated yet, named rather than left for a reader to
    /// notice one `null` at a time.
    ///
    /// Read from `LifterFacts` rather than worked out here, so this list and the
    /// one `unstated_facts` reports are the same list. Two places
    /// counting the record's empty fields separately would eventually disagree,
    /// and a reader told one thing by the resource and another by the tool has
    /// no way to tell which is right.
    private var unstatedFacts: [String] {
        LifterFacts.unstated(in: snapshot).map(\.name)
    }

    // MARK: - What he is on

    private var currentBlock: JSONValue {
        guard let plan = TrainingLog.currentBlock(in: snapshot) else { return .null }
        return [
            "title": .string(plan.title),
            "goal": .string(plan.goal),
            "startDate": .date(plan.startDate),
            "weekCount": .integer(plan.weekCount),
            "weekdays": .array(plan.weekdays.map { .string($0.fullName) }),
            "durationMinutes": .integer(plan.durationMinutes),
            "weeksPrescribed": .integer(plan.weeks.count),
            "weeksLogged": .integer(
                plan.weeks.count { week in
                    week.days.contains { $0.exercises.contains { !$0.loggedSets.isEmpty } }
                }),
            "days": .array(
                plan.weeks.flatMap(\.days).map {
                    [
                        "weekday": .string($0.weekday.fullName),
                        "focus": .string($0.focus),
                        "exercises": .array(
                            $0.exercises.map { .string($0.displayName) }),
                    ]
                }),
        ]
    }

    // MARK: - What he did lately

    private var recentSessions: JSONValue {
        .array(
            TrainingLog.sessions(in: snapshot).prefix(Self.carriedSessions).map { session in
                [
                    "date": session.date.map { .date($0) } ?? .null,
                    "plan": .string(session.planTitle),
                    "week": .integer(session.weekOrdinal),
                    "weekday": .string(session.weekday.fullName),
                    "focus": .string(session.focus),
                    "exercises": .array(
                        session.exercises.map { exercise in
                            .string(
                                "\(exercise.displayName): "
                                    + "\(exercise.loggedSets.count { $0.isCompleted && !$0.isWarmup })"
                                    + " of \(exercise.targetSets) working sets")
                        }),
                ]
            })
    }

    // MARK: - What he is working with

    /// What he last worked with on each lift, and — beside it — the effort the
    /// plan had asked for on that lift.
    ///
    /// `rpe` is what he reported; `prescribedIntensity` is what was prescribed,
    /// on whatever scale it was prescribed on. Both are here so the comparison
    /// can be drawn; nothing here draws it, converts an RIR into an RPE, or
    /// concludes that a target was met. A lift with no stated target reports
    /// `null`, which means nobody stated one — not that it was easy.
    private var workingWeights: JSONValue {
        .array(
            TrainingLog.lastWorkingSets(in: snapshot).map { record in
                [
                    "exerciseID": .string(record.exercise.exerciseID.rawValue),
                    "displayName": .string(record.exercise.displayName),
                    "load": .mass(record.loggedSet.load),
                    "reps": .integer(record.loggedSet.reps),
                    "rpe": record.loggedSet.rpe.map { .number($0) } ?? .null,
                    "prescribedIntensity": .intensity(record.exercise.intensity),
                    "lastTrained": .date(record.loggedSet.completedAt),
                ]
            })
    }

    // MARK: - Where to go for more

    private var note: String {
        opening
            + "This is a summary. For depth: \(ToolCatalog.listExercises) for real exercise "
            + "IDs he can perform, \(ToolCatalog.exerciseHistory) for every set on one "
            + "movement, \(ToolCatalog.recentSessions) for full session detail, and "
            + "\(ToolCatalog.volumeByMuscle) for set and rep totals. Write a plan with "
            + "\(ToolCatalog.writePlan), using IDs from \(ToolCatalog.listExercises) verbatim."
    }

    /// What to say before the summary when there is nothing, or not enough, to
    /// summarize. The app has no setup screen, so an empty profile is a
    /// conversation that has not happened rather than a step he skipped.
    private var opening: String {
        guard snapshot.profile != nil else {
            return "Nothing has been recorded about this lifter — the app asks him nothing, so "
                + "everything known about him comes from what he tells you. Not one fact this "
                + "record can hold is stated; \(ToolCatalog.unstatedFacts) names them and says "
                + "what each holds. Assume nothing; ask, then write it down with "
                + "\(ToolCatalog.updateProfile). "
        }
        let unstated = unstatedFacts
        guard !unstated.isEmpty else { return "" }
        return "He has not stated: \(unstated.joined(separator: ", ")). Those read as null "
            + "above and are genuinely unknown, not defaults — do not assume a value for one. "
            + "\(ToolCatalog.unstatedFacts) says what each of them holds. Record what he tells "
            + "you with \(ToolCatalog.updateProfile). "
    }
}
