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

    private var lifter: JSONValue {
        guard let profile = snapshot.profile else { return .null }
        return [
            "experience": .string(profile.experience.rawValue),
            "goal": .string(profile.goal),
            "constraints": .string(profile.constraints),
            "equipmentAccess": .string(profile.equipmentAccess.rawValue),
            "availableEquipment": .taxonomy(profile.availableEquipment),
            "avoidedPatterns": .taxonomy(profile.avoidedPatterns),
            "avoidedExercises": .array(profile.avoidedExercises.map { .string($0.rawValue) }),
            "preferredWeekdays": .array(profile.preferredWeekdays.map { .string($0.fullName) }),
            "preferredDurationMinutes": .integer(profile.preferredDurationMinutes),
            "displayUnit": .string(profile.displayUnit.rawValue),
            "bodyweight": .mass(profile.bodyweight ?? snapshot.bodyMetrics.last?.bodyweight),
            "hasCompletedSetup": .bool(profile.hasCompletedSetup),
        ]
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

    private var workingWeights: JSONValue {
        .array(
            TrainingLog.lastWorkingSets(in: snapshot).map { record in
                [
                    "exerciseID": .string(record.exercise.exerciseID.rawValue),
                    "displayName": .string(record.exercise.displayName),
                    "load": .mass(record.loggedSet.load),
                    "reps": .integer(record.loggedSet.reps),
                    "rpe": record.loggedSet.rpe.map { .number($0) } ?? .null,
                    "lastTrained": .date(record.loggedSet.completedAt),
                ]
            })
    }

    // MARK: - Where to go for more

    private var note: String {
        let opening =
            snapshot.profile == nil
            ? "This lifter has not been set up yet — no equipment, goal or constraints have "
                + "been recorded, so nothing about him should be assumed. "
            : ""
        return opening
            + "This is a summary. For depth: \(ToolCatalog.listExercises) for real exercise "
            + "IDs he can perform, \(ToolCatalog.exerciseHistory) for every set on one "
            + "movement, \(ToolCatalog.recentSessions) for full session detail, and "
            + "\(ToolCatalog.volumeByMuscle) for set and rep totals. Write a plan with "
            + "\(ToolCatalog.writePlan), using IDs from \(ToolCatalog.listExercises) verbatim."
    }
}
