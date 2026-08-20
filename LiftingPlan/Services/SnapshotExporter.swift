import Foundation
import SwiftData
import LiftingKit

/// Turns the stored SwiftData graph into a `TrainingSnapshot`.
///
/// Call `export(from:catalogVersion:)` with the app's `ModelContext` and the
/// version of the catalog currently loaded; hand the result to a
/// `DocumentTransport` to put it where Claude can read it. This is the only
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
        // When each stated fact was last spoken to. Read here rather than off
        // the profile because the profile holds one date for all of them.
        let statedAt = StatedFacts.dates(
            in: try context.fetch(FetchDescriptor<ProfileStatement>()))
        let plans = try context.fetch(FetchDescriptor<TrainingPlan>(
            sortBy: [SortDescriptor(\.startDate)]
        ))

        return TrainingSnapshot(
            catalogVersion: catalogVersion,
            generatedAt: generatedAt,
            profile: profiles.first.map { snapshot(of: $0, statedAt: statedAt) },
            bodyMetrics: metrics.map(snapshot(of:)),
            baselines: baselines.map(snapshot(of:)),
            routines: plans.compactMap(routine(of:)),
            log: log(of: plans),
            lifterNotes: lifterNotes(of: plans)
        )
    }

    /// The profile, with what nobody has stated left absent.
    ///
    /// `experience` and the equipment he owns cross as `nil` when they have not
    /// been stated. This is the one place that could quietly turn "not known"
    /// into a plausible default on the way out, and a reader given "Full gym,
    /// Intermediate" about someone who never said so has no way to tell it from
    /// a fact. `availableEquipment` is `nil` for the same reason rather than
    /// empty: empty says he can perform nothing.
    private static func snapshot(
        of profile: UserProfile, statedAt: [String: Date]
    ) -> SnapshotProfile {
        SnapshotProfile(
            displayUnit: profile.displayUnit,
            experience: profile.experience,
            availableEquipment: profile.permittedEquipment?
                .sorted { $0.rawValue < $1.rawValue },
            goal: profile.goal,
            constraints: profile.constraints,
            bodyweight: profile.bodyweight,
            avoidedPatterns: profile.avoidedPatterns.sorted { $0.rawValue < $1.rawValue },
            avoidedExercises: profile.avoidedExercises.sorted { $0.rawValue < $1.rawValue },
            preferredWeekdays: profile.orderedPreferredWeekdays,
            preferredDurationMinutes: profile.preferredDurationMinutes,
            // Carried so the writer of the next update can tell one still
            // waiting in the folder from one already taken in.
            appliedProfileUpdateID: profile.appliedProfileUpdateID,
            // When he said each of these, rather than one date for all of them.
            // The profile's own `updatedAt` moves whenever any fact changes, so
            // it could never say whether a constraint is current — see
            // `SnapshotProfile.statedAt`.
            statedAt: statedAt
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

    /// One block: the document the coach wrote, and the three things the store
    /// knows that it cannot.
    ///
    /// **The document is read back rather than restated.** It used to be copied
    /// into a parallel tree of snapshot types, which described a superset in a
    /// different shape from the format that prescribed it — flattened here,
    /// nested there — and had to be kept in step by hand.
    /// `PlanDocument(reconstructing:)` is the one mapping now, and its round-trip
    /// suite is what says the store holds everything the document stated.
    ///
    /// A block whose store row carries no document identity cannot be
    /// reconstructed, and is left out rather than sent as an invented one.
    /// Nothing in the app can produce such a row — `PlanImporter` is the only
    /// producer and it writes all three fields — so this is an absence that
    /// should never occur, reported as an absence rather than as a plan.
    private static func routine(of plan: TrainingPlan) -> SnapshotRoutine? {
        guard let document = PlanDocument(reconstructing: plan) else { return nil }
        return SnapshotRoutine(
            document: document,
            startDate: plan.startDate,
            completedAt: plan.completedAt,
            sessions: plan.orderedWeeks.flatMap { week in
                week.orderedDays.map { day in
                    SnapshotSession(
                        blockOrdinal: week.ordinal, weekday: day.weekday,
                        completedAt: day.completedAt)
                }
            }
        )
    }

    /// Everything the lifter wrote about performing a movement, flat.
    ///
    /// **The one thing in the record the coach cannot infer.** A knee that hurt
    /// on the last set does not appear in a load or a rep count, and it is
    /// exactly the fact that should change what comes next. It travels beside
    /// the log rather than inside the plan, because the plan is his and this is
    /// not.
    private static func lifterNotes(of plans: [TrainingPlan]) -> [LifterNote] {
        var notes: [LifterNote] = []
        for plan in plans {
            guard let routineID = plan.sourceDocumentID else { continue }
            for week in plan.orderedWeeks {
                for day in week.orderedDays {
                    for exercise in day.orderedExercises {
                        guard let text = exercise.lifterNote, !text.isEmpty else { continue }
                        notes.append(LifterNote(
                            routineID: routineID, blockOrdinal: week.ordinal,
                            weekday: day.weekday, exerciseOrder: exercise.order,
                            exerciseID: exercise.exerciseID, text: text))
                    }
                }
            }
        }
        return notes
    }

    /// Every set ever logged, flat and oldest first.
    ///
    /// **The shape every reader wanted.** The sets used to travel nested inside
    /// the exercise inside the day inside the week inside the plan, and each
    /// reading tool began by flattening them; the flattening is done once, here,
    /// on the way out. Each row names where it sits — block, week ordinal,
    /// weekday, the movement's position in the day — so what was prescribed for
    /// it is a lookup into that block's document.
    ///
    /// `exerciseOrder` is the movement's stored `order`, which is its identity
    /// within the day: the same movement may be prescribed twice, and the
    /// position is what tells the two apart.
    ///
    /// Warm-ups and rows nobody ticked go out flagged rather than filtered: a
    /// reader deciding what counts as work has to see what was there.
    private static func log(of plans: [TrainingPlan]) -> [LoggedSetRecord] {
        var records: [LoggedSetRecord] = []
        for plan in plans {
            guard let routineID = plan.sourceDocumentID else { continue }
            for week in plan.orderedWeeks {
                for day in week.orderedDays {
                    for exercise in day.orderedExercises {
                        for set in (exercise.loggedSets ?? []).sorted(by: { $0.setIndex < $1.setIndex }) {
                            records.append(LoggedSetRecord(
                                routineID: routineID,
                                blockOrdinal: week.ordinal,
                                weekday: day.weekday,
                                exerciseOrder: exercise.order,
                                exerciseID: exercise.exerciseID,
                                setIndex: set.setIndex,
                                isWarmup: set.isWarmup,
                                isCompleted: set.isCompleted,
                                completedAt: set.completedAt,
                                load: set.load,
                                reps: set.reps,
                                durationSeconds: set.durationSeconds,
                                distance: set.distance
                            ))
                        }
                    }
                }
            }
        }
        // Oldest first, and ties broken by where the set sits. Two sets ticked
        // in the same second are ordinary — a lifter filling in a table he
        // already trained does it in one breath — and a sort that left their
        // order to chance would report a different history each time the
        // snapshot was written.
        return records.sorted {
            ($0.completedAt, $0.blockOrdinal, $0.exerciseOrder, $0.setIndex)
                < ($1.completedAt, $1.blockOrdinal, $1.exerciseOrder, $1.setIndex)
        }
    }
}
