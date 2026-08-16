import Foundation
import LiftingKit
@testable import LiftingMCPKit

// The Mac this is written on has no iCloud account, so the real shared folder
// does not exist here. Everything below stands in for it: a fixture snapshot
// with a finished block and a running one, a small catalog of real MoveKit
// slugs, and an in-memory transport that can be empty, full, or broken.

/// A fixed instant so a window is a window and not a race. Sits on a second
/// boundary, so ISO 8601 round-trips it exactly.
let referenceNow = Date(timeIntervalSince1970: 1_760_000_000)

func daysAgo(_ days: Int) -> Date {
    referenceNow.addingTimeInterval(TimeInterval(-days) * 24 * 60 * 60)
}

// MARK: - The catalog

/// A handful of real catalog entries, decoded rather than constructed —
/// `Exercise` has no public initializer, which is the guard that stops anything
/// outside the package minting an entry the catalog does not have.
///
/// Every ID and every muscle list below is copied from the real
/// `exercises.json`, so a test that passes here is testing the real shapes.
func fixtureCatalog(version: Int = 5) throws -> ExerciseCatalog {
    let json = """
        [
          {"id": "barbell-bench-press", "displayName": "Barbell Bench Press",
           "primaryMuscles": ["chest"], "secondaryMuscles": ["triceps", "shoulders"],
           "equipment": "barbell", "pattern": "horizontal press", "force": "push",
           "mechanic": "compound", "category": "strength", "difficulty": "intermediate"},
          {"id": "barbell-squat", "displayName": "Barbell Squat",
           "primaryMuscles": ["quadriceps"],
           "secondaryMuscles": ["calves", "glutes", "hamstrings", "lower back"],
           "equipment": "barbell", "pattern": "squat", "force": "push",
           "mechanic": "compound", "category": "strength", "difficulty": "intermediate"},
          {"id": "barbell-bent-over-row", "displayName": "Barbell Bent Over Row",
           "aliases": ["bent over barbell row"], "primaryMuscles": ["middle back"],
           "secondaryMuscles": ["biceps", "lats", "shoulders"],
           "equipment": "barbell", "pattern": "horizontal pull", "force": "pull",
           "mechanic": "compound", "category": "strength", "difficulty": "intermediate"},
          {"id": "lat-pulldown", "displayName": "Lat Pulldown",
           "primaryMuscles": ["lats"], "secondaryMuscles": ["biceps", "middle back"],
           "equipment": "cable", "pattern": "vertical pull", "force": "pull",
           "mechanic": "compound", "category": "strength", "difficulty": "beginner"},
          {"id": "barbell-curl", "displayName": "Barbell Curl",
           "primaryMuscles": ["biceps"], "secondaryMuscles": ["forearms"],
           "equipment": "barbell", "pattern": "curl", "force": "pull",
           "mechanic": "isolation", "category": "strength", "difficulty": "beginner"},
          {"id": "dumbbell-bench-press", "displayName": "Dumbbell Bench Press",
           "primaryMuscles": ["chest"], "secondaryMuscles": ["triceps", "shoulders"],
           "equipment": "dumbbell", "pattern": "horizontal press", "force": "push",
           "mechanic": "compound", "category": "strength", "difficulty": "intermediate"},
          {"id": "push-up", "displayName": "Push Up",
           "primaryMuscles": ["chest"], "secondaryMuscles": ["triceps", "shoulders"],
           "equipment": "bodyweight", "pattern": "horizontal press", "force": "push",
           "mechanic": "compound", "category": "strength", "difficulty": "intermediate"},
          {"id": "barbell-deadlift", "displayName": "Barbell Deadlift",
           "primaryMuscles": ["lower back"],
           "secondaryMuscles": ["glutes", "hamstrings", "quadriceps", "traps"],
           "equipment": "barbell", "pattern": "hinge", "force": "pull",
           "mechanic": "compound", "category": "strength", "difficulty": "intermediate"}
        ]
        """
    let exercises = try JSONDecoder().decode([Exercise].self, from: Data(json.utf8))
    return ExerciseCatalog(exercises: exercises, version: version)
}

// MARK: - The snapshot

func fixtureProfile(
    experience: ExperienceLevel? = .intermediate,
    equipmentAccess: Equipment? = .fullGym,
    availableEquipment: [EquipmentType]? = [
        .bodyweight, .barbell, .dumbbell, .plate, .band, .kettlebell,
        .medicineBall, .machine, .cable, .ezBar, .trapBar, .sled, .cardioMachine, .other,
    ],
    avoidedPatterns: [MovementPattern] = [],
    avoidedExercises: [ExerciseID] = [],
    appliedProfileUpdateID: UUID? = nil
) -> SnapshotProfile {
    SnapshotProfile(
        displayUnit: .pounds,
        experience: experience,
        equipmentAccess: equipmentAccess,
        availableEquipment: availableEquipment,
        goal: "Add 20 lb to the bench",
        constraints: "Left shoulder is touchy overhead",
        bodyweight: Mass(value: 182, unit: .pounds),
        avoidedPatterns: avoidedPatterns,
        avoidedExercises: avoidedExercises,
        preferredWeekdays: [.monday, .thursday],
        preferredDurationMinutes: 60,
        appliedProfileUpdateID: appliedProfileUpdateID,
        updatedAt: daysAgo(60)
    )
}

private func set(
    _ index: Int, _ pounds: Double?, _ reps: Int, at date: Date,
    rpe: Double? = nil, warmup: Bool = false, completed: Bool = true
) -> SnapshotLoggedSet {
    SnapshotLoggedSet(
        setIndex: index,
        load: pounds.map { Mass(value: $0, unit: .pounds) },
        reps: reps, rpe: rpe, isCompleted: completed, isWarmup: warmup, completedAt: date
    )
}

private func prescribed(
    _ id: String, _ name: String, order: Int, sets: Int, reps: String,
    load: Double?, rest: Int?, logged: [SnapshotLoggedSet] = []
) -> SnapshotPlannedExercise {
    SnapshotPlannedExercise(
        exerciseID: ExerciseID(rawValue: id), displayName: name, order: order,
        targetSets: sets, repRange: reps,
        suggestedLoad: load.map { Mass(value: $0, unit: .pounds) },
        restSeconds: rest, tempo: nil, notes: nil, loggedSets: logged
    )
}

/// The finished block: one full-body day, thirty days ago.
private func basePlan() -> SnapshotPlan {
    let day = daysAgo(30)
    return SnapshotPlan(
        title: "Base block", goal: "Get the lifts moving", startDate: daysAgo(60),
        weekCount: 4, completedAt: daysAgo(14), catalogVersion: 5,
        weekdays: [.monday], durationMinutes: 50,
        weeks: [
            SnapshotWeek(
                ordinal: 1, label: "Introduction", isDeload: false,
                days: [
                    SnapshotDay(
                        weekday: .monday, focus: "Full body", durationMinutes: 50,
                        completedAt: day,
                        exercises: [
                            prescribed(
                                "barbell-bench-press", "Barbell Bench Press", order: 0,
                                sets: 3, reps: "5", load: 215, rest: 180,
                                logged: [
                                    set(0, 135, 5, at: day, warmup: true),
                                    set(1, 215, 5, at: day, rpe: 7),
                                    set(2, 215, 5, at: day, rpe: 8),
                                    set(3, 215, 5, at: day, rpe: 9),
                                ]),
                            prescribed(
                                "barbell-squat", "Barbell Squat", order: 1,
                                sets: 3, reps: "5", load: 275, rest: 210,
                                logged: [
                                    set(0, 275, 5, at: day),
                                    set(1, 275, 5, at: day),
                                    set(2, 275, 5, at: day),
                                ]),
                        ])
                ])
        ])
}

/// The running block: a pull day four days ago, a push day two days ago, and a
/// second week that has been prescribed but not trained.
private func currentPlan() -> SnapshotPlan {
    let pullDay = daysAgo(4)
    let pushDay = daysAgo(2)
    return SnapshotPlan(
        title: "Autumn strength", goal: "Add 20 lb to the bench", startDate: daysAgo(14),
        weekCount: 4, completedAt: nil, catalogVersion: 5,
        weekdays: [.monday, .thursday], durationMinutes: 60,
        weeks: [
            SnapshotWeek(
                ordinal: 1, label: "Accumulation", isDeload: false,
                days: [
                    SnapshotDay(
                        weekday: .thursday, focus: "Pull", durationMinutes: 60,
                        completedAt: pullDay,
                        exercises: [
                            prescribed(
                                "barbell-bent-over-row", "Barbell Bent Over Row", order: 0,
                                sets: 3, reps: "8", load: 185, rest: 120,
                                logged: [
                                    set(0, 95, 8, at: pullDay, warmup: true),
                                    set(1, 185, 8, at: pullDay),
                                    set(2, 185, 8, at: pullDay),
                                    set(3, 185, 7, at: pullDay),
                                ]),
                            prescribed(
                                "lat-pulldown", "Lat Pulldown", order: 1,
                                sets: 3, reps: "12", load: 120, rest: 90,
                                logged: [
                                    set(0, 120, 12, at: pullDay),
                                    set(1, 120, 12, at: pullDay),
                                    set(2, 120, 12, at: pullDay),
                                ]),
                        ]),
                    SnapshotDay(
                        weekday: .monday, focus: "Push", durationMinutes: 60,
                        completedAt: pushDay,
                        exercises: [
                            prescribed(
                                "barbell-bench-press", "Barbell Bench Press", order: 0,
                                sets: 3, reps: "5", load: 225, rest: 180,
                                logged: [
                                    set(0, 135, 5, at: pushDay, warmup: true),
                                    set(1, 225, 5, at: pushDay, rpe: 8),
                                    set(2, 225, 5, at: pushDay, rpe: 8.5),
                                    set(3, 225, 4, at: pushDay, rpe: 9.5),
                                    // On screen but never finished.
                                    set(4, 225, 0, at: pushDay, completed: false),
                                ]),
                            prescribed(
                                "barbell-curl", "Barbell Curl", order: 1,
                                sets: 3, reps: "10", load: 65, rest: 60,
                                logged: [
                                    set(0, 65, 10, at: pushDay),
                                    set(1, 65, 10, at: pushDay),
                                    set(2, 65, 10, at: pushDay),
                                ]),
                        ]),
                ]),
            SnapshotWeek(
                ordinal: 2, label: "Accumulation", isDeload: false,
                days: [
                    SnapshotDay(
                        weekday: .monday, focus: "Push", durationMinutes: 60,
                        completedAt: nil,
                        exercises: [
                            prescribed(
                                "barbell-bench-press", "Barbell Bench Press", order: 0,
                                sets: 3, reps: "5", load: 230, rest: 180)
                        ])
                ]),
        ])
}

func fixtureSnapshot(
    profile: SnapshotProfile? = fixtureProfile(),
    plans: [SnapshotPlan]? = nil,
    catalogVersion: Int = 5
) -> TrainingSnapshot {
    TrainingSnapshot(
        catalogVersion: catalogVersion,
        generatedAt: daysAgo(1),
        profile: profile,
        bodyMetrics: [
            SnapshotBodyMetric(date: daysAgo(30), bodyweight: Mass(value: 178, unit: .pounds)),
            SnapshotBodyMetric(date: daysAgo(2), bodyweight: Mass(value: 182, unit: .pounds)),
        ],
        baselines: [
            SnapshotBaseline(
                exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
                load: Mass(value: 205, unit: .pounds), reps: 5, recordedAt: daysAgo(90))
        ],
        plans: plans ?? [basePlan(), currentPlan()]
    )
}

// MARK: - The transport

/// The shared folder, in memory.
///
/// Holds whatever snapshot it was given and remembers the plan last written to
/// it, and can be told to fail, so a tool's handling of "nothing yet", "here is
/// the data", and "the folder is broken" can all be covered without a disk or
/// an iCloud account.
final class InMemoryDocuments: TrainingDocuments, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: TrainingSnapshot?
    private var written: PlanDocument?
    private var writtenProfileUpdate: ProfileUpdate?
    private var failure: (any Error)?

    struct Broken: Error, LocalizedError {
        var errorDescription: String? { "the volume is not readable" }
    }

    init(snapshot: TrainingSnapshot? = nil) {
        self.snapshot = snapshot
    }

    var snapshotLocation: String { "/fixture/Documents/snapshot.json" }
    var planLocation: String { "/fixture/Documents/plan.json" }
    var profileUpdateLocation: String { "/fixture/Documents/profile-update.json" }

    var lastWrittenPlan: PlanDocument? { lock.withLock { written } }
    var lastWrittenProfileUpdate: ProfileUpdate? { lock.withLock { writtenProfileUpdate } }

    func breakTransport() { lock.withLock { failure = Broken() } }

    func readSnapshot() throws -> TrainingSnapshot? {
        try lock.withLock {
            if let failure { throw failure }
            return snapshot
        }
    }

    func writePlan(_ plan: PlanDocument) throws {
        try lock.withLock {
            if let failure { throw failure }
            written = plan
        }
    }

    func writeProfileUpdate(_ update: ProfileUpdate) throws {
        try lock.withLock {
            if let failure { throw failure }
            writtenProfileUpdate = update
        }
    }

    func readProfileUpdate() throws -> ProfileUpdate? {
        try lock.withLock {
            if let failure { throw failure }
            return writtenProfileUpdate
        }
    }
}

// MARK: - Calling a tool in a test

func makeRunner(
    documents: any TrainingDocuments,
    catalog: (any ExerciseCatalogProviding)? = nil
) throws -> ToolRunner {
    ToolRunner(
        documents: documents,
        catalog: try catalog ?? fixtureCatalog(),
        now: { referenceNow }
    )
}

extension ToolOutcome {

    /// The report inside, or `nil` when the tool failed.
    var report: JSONValue? {
        if case .report(let value) = self { return value }
        return nil
    }

    /// The failure message inside, or `nil` when the tool reported.
    var failureMessage: String? {
        if case .failure(let message) = self { return message }
        return nil
    }
}
