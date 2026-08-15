import Foundation
import SwiftData
import LiftingKit

/// Turns the stored SwiftData graph into a `TrainingSnapshot`.
///
/// Call `export(from:catalogVersion:)` with the app's `ModelContext` and the
/// version of the catalog currently loaded; hand the result to a
/// `SnapshotWriting` to put it where Claude can read it. This is the only
/// place that knows both SwiftData and the document format, which is what
/// keeps the format free of persistence — the macOS server links the same
/// document types and never links SwiftData.
///
/// It reports and never concludes. Every value is copied across exactly as
/// stored: no weight is converted to a common unit, no missing rest becomes a
/// number, and no empty rep range is filled in. An empty store is a normal
/// outcome, not an error — a lifter who has logged nothing still has an
/// identity worth sending.
///
/// Depends on: the `Store/` models and `TrainingSnapshot` from `LiftingKit`.
enum SnapshotExporter {

    /// Reads the whole store and returns it as one document.
    ///
    /// `catalogVersion` is the `ExerciseCatalogProviding.version` in force at
    /// export time; it is stamped on the snapshot so a reader can tell which
    /// generation of exercise data the IDs inside were selected from. It has
    /// no default — the stamp is only meaningful if the caller states where
    /// its catalog came from.
    ///
    /// Throws whatever the fetches throw. A snapshot that could only be
    /// partially read is not written at all: a document that silently omits a
    /// training block would look exactly like a lifter who never trained.
    static func export(
        from context: ModelContext,
        catalogVersion: Int,
        generatedAt: Date = Date()
    ) throws -> TrainingSnapshot {
        // Exactly one profile is expected, but CloudKit cannot enforce
        // uniqueness, so the most recently updated one is the honest answer if
        // a duplicate ever syncs in.
        let profiles = try context.fetch(FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))
        let metrics = try context.fetch(FetchDescriptor<BodyMetric>(
            sortBy: [SortDescriptor(\.date)]
        ))
        let baselines = try context.fetch(FetchDescriptor<StrengthBaseline>(
            sortBy: [SortDescriptor(\.recordedAt)]
        ))
        let plans = try context.fetch(FetchDescriptor<TrainingPlan>(
            sortBy: [SortDescriptor(\.startDate)]
        ))

        return TrainingSnapshot(
            catalogVersion: catalogVersion,
            generatedAt: generatedAt,
            profile: profiles.first.map(snapshot(of:)),
            bodyMetrics: metrics.map(snapshot(of:)),
            baselines: baselines.map(snapshot(of:)),
            plans: plans.map(snapshot(of:))
        )
    }

    private static func snapshot(of profile: UserProfile) -> SnapshotProfile {
        SnapshotProfile(
            displayUnit: profile.displayUnit,
            experience: profile.experience,
            equipmentAccess: profile.equipmentAccess,
            availableEquipment: profile.permittedEquipment
                .sorted { $0.rawValue < $1.rawValue },
            goal: profile.goal,
            constraints: profile.constraints,
            bodyweight: profile.bodyweight,
            avoidedPatterns: profile.avoidedPatterns.sorted { $0.rawValue < $1.rawValue },
            avoidedExercises: profile.avoidedExercises.sorted { $0.rawValue < $1.rawValue },
            preferredWeekdays: profile.orderedPreferredWeekdays,
            preferredDurationMinutes: profile.preferredDurationMinutes,
            hasCompletedSetup: profile.hasCompletedSetup,
            updatedAt: profile.updatedAt
        )
    }

    private static func snapshot(of metric: BodyMetric) -> SnapshotBodyMetric {
        SnapshotBodyMetric(date: metric.date, bodyweight: metric.bodyweight)
    }

    private static func snapshot(of baseline: StrengthBaseline) -> SnapshotBaseline {
        SnapshotBaseline(
            exerciseID: baseline.exerciseID, load: baseline.load,
            reps: baseline.reps, recordedAt: baseline.recordedAt
        )
    }

    private static func snapshot(of plan: TrainingPlan) -> SnapshotPlan {
        SnapshotPlan(
            title: plan.title, goal: plan.goal, startDate: plan.startDate,
            weekCount: plan.weekCount, completedAt: plan.completedAt,
            catalogVersion: plan.catalogVersion, weekdays: plan.orderedWeekdays,
            durationMinutes: plan.durationMinutes,
            weeks: plan.orderedWeeks.map(snapshot(of:))
        )
    }

    private static func snapshot(of week: TrainingWeek) -> SnapshotWeek {
        SnapshotWeek(
            ordinal: week.ordinal, label: week.label, isDeload: week.isDeload,
            days: week.orderedDays.map(snapshot(of:))
        )
    }

    private static func snapshot(of day: WorkoutDay) -> SnapshotDay {
        SnapshotDay(
            weekday: day.weekday, focus: day.focus,
            durationMinutes: day.durationMinutes, completedAt: day.completedAt,
            exercises: day.orderedExercises.map(snapshot(of:))
        )
    }

    private static func snapshot(of exercise: PlannedExercise) -> SnapshotPlannedExercise {
        SnapshotPlannedExercise(
            exerciseID: exercise.exerciseID, displayName: exercise.displayName,
            order: exercise.order, targetSets: exercise.targetSets,
            repRange: exercise.repRange, suggestedLoad: exercise.suggestedLoad,
            restSeconds: exercise.restSeconds, tempo: exercise.tempo,
            notes: exercise.notes,
            // Warmups and unfinished rows are carried too, labelled rather
            // than filtered: what was skipped is as informative as what was
            // done, and deciding what to make of it is not the app's call.
            loggedSets: (exercise.loggedSets ?? [])
                .sorted { $0.setIndex < $1.setIndex }
                .map(snapshot(of:))
        )
    }

    private static func snapshot(of set: LoggedSet) -> SnapshotLoggedSet {
        SnapshotLoggedSet(
            setIndex: set.setIndex, load: set.load, reps: set.reps, rpe: set.rpe,
            isCompleted: set.isCompleted, isWarmup: set.isWarmup,
            completedAt: set.completedAt
        )
    }
}
