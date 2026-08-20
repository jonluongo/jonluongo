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

// MARK: - Building a block

// A block is written as a `PlanDocument` and the work against it as a flat log,
// so a fixture has to produce both and keep them keyed to each other. These
// builders mirror the nesting the fixtures used to be written in — set, then
// exercise, then day, then block — and hand back the two halves the wire
// carries.

/// One logged set, before it knows where it sits. `Fixture.day` gives it its
/// position, which is the only thing it cannot know about itself.
struct FixtureSet {
    var index: Int
    var pounds: Double?
    var reps: Int
    var date: Date
    var warmup = false
    var completed = true
    var durationSeconds: Int?
    var distance: Distance?
}

func set(
    _ index: Int, _ pounds: Double?, _ reps: Int, at date: Date,
    warmup: Bool = false, completed: Bool = true,
    durationSeconds: Int? = nil, distance: Distance? = nil
) -> FixtureSet {
    FixtureSet(
        index: index, pounds: pounds, reps: reps, date: date, warmup: warmup,
        completed: completed, durationSeconds: durationSeconds, distance: distance)
}

/// One movement of a day: what was prescribed, and what was logged against it.
struct FixtureExercise {
    var exercise: PlanDocumentExercise
    var logged: [FixtureSet]
}

func prescribed(
    _ id: String, _ name: String, order: Int = 0, sets: Int, reps: String,
    load: Double?, rest: Int?, intensity: IntensityTarget? = nil,
    logged: [FixtureSet] = []
) -> FixtureExercise {
    FixtureExercise(
        exercise: PlanDocumentExercise(
            exerciseID: ExerciseID(rawValue: id), displayName: name, sets: sets,
            repRange: reps, restSeconds: rest,
            suggestedLoad: load.map { Mass(value: $0, unit: .pounds) },
            intensity: intensity),
        logged: logged)
}

/// One prescribed day and everything logged on it.
struct FixtureDay {
    var day: PlanDocumentDay
    var completedAt: Date?
    /// The day's sets, each already knowing which movement it belongs to.
    var logged: [(order: Int, set: FixtureSet)]
}

func fixtureDay(
    weekday: Weekday, focus: String = "", durationMinutes: Int? = nil,
    completedAt: Date? = nil, exercises: [FixtureExercise] = [],
    groups: [PlanDocumentGroup] = []
) -> FixtureDay {
    let entries = exercises.map { PlanDocumentEntry.exercise($0.exercise) }
        + groups.map(PlanDocumentEntry.group)
    var logged: [(order: Int, set: FixtureSet)] = []
    for (order, exercise) in exercises.enumerated() {
        logged += exercise.logged.map { (order, $0) }
    }
    return FixtureDay(
        day: PlanDocumentDay(
            weekday: weekday, focus: focus, durationMinutes: durationMinutes,
            entries: entries),
        completedAt: completedAt, logged: logged)
}

/// A block: the document, the sessions the record knows about, and the log.
func fixtureRoutine(
    id: UUID = UUID(), title: String, goal: String = "", startDate: Date,
    completedAt: Date? = nil, durationMinutes: Int? = nil, catalogVersion: Int = 5,
    blocks: [(label: String?, isDeload: Bool, days: [FixtureDay])]
) -> (routine: SnapshotRoutine, log: [LoggedSetRecord]) {
    var sessions: [SnapshotSession] = []
    var log: [LoggedSetRecord] = []
    for (index, block) in blocks.enumerated() {
        let ordinal = index + 1
        for day in block.days {
            sessions.append(SnapshotSession(
                blockOrdinal: ordinal, weekday: day.day.weekday, completedAt: day.completedAt))
            let byOrder = day.day.entries.flatMap(\.exercises)
            for (order, set) in day.logged {
                guard byOrder.indices.contains(order) else { continue }
                log.append(LoggedSetRecord(
                    routineID: id, blockOrdinal: ordinal, weekday: day.day.weekday,
                    exerciseOrder: order, exerciseID: byOrder[order].exerciseID,
                    setIndex: set.index, isWarmup: set.warmup, isCompleted: set.completed,
                    completedAt: set.date,
                    load: set.pounds.map { Mass(value: $0, unit: .pounds) },
                    reps: set.reps, durationSeconds: set.durationSeconds,
                    distance: set.distance))
            }
        }
    }
    let routine = SnapshotRoutine(
        document: PlanDocument(
            id: id, catalogVersion: catalogVersion, generatedAt: startDate,
            title: title, goal: goal, durationMinutes: durationMinutes,
            blocks: blocks.map {
                PlanDocumentBlock(label: $0.label, isDeload: $0.isDeload, days: $0.days.map(\.day))
            }),
        startDate: startDate, completedAt: completedAt, sessions: sessions)
    return (routine, log)
}

/// The finished block: one full-body day, thirty days ago.
private func basePlan() -> (routine: SnapshotRoutine, log: [LoggedSetRecord]) {
    let day = daysAgo(30)
    return fixtureRoutine(
        title: "Base block", goal: "Get the lifts moving", startDate: daysAgo(60),
        completedAt: daysAgo(14), durationMinutes: 50,
        blocks: [(
            label: "Introduction", isDeload: false,
            days: [
                fixtureDay(
                    weekday: .monday, focus: "Full body", durationMinutes: 50,
                    completedAt: day,
                    exercises: [
                        prescribed(
                            "barbell-bench-press", "Barbell Bench Press",
                            sets: 3, reps: "5", load: 215, rest: 180,
                            logged: [
                                set(0, 135, 5, at: day, warmup: true),
                                set(1, 215, 5, at: day),
                                set(2, 215, 5, at: day),
                                set(3, 215, 5, at: day),
                            ]),
                        prescribed(
                            "barbell-squat", "Barbell Squat",
                            sets: 3, reps: "5", load: 275, rest: 210,
                            logged: [
                                set(0, 275, 5, at: day),
                                set(1, 275, 5, at: day),
                                set(2, 275, 5, at: day),
                            ]),
                    ])
            ])])
}

/// The running block: a pull day four days ago, a push day two days ago, and a
/// second week that has been prescribed but not trained.
private func currentPlan() -> (routine: SnapshotRoutine, log: [LoggedSetRecord]) {
    let pullDay = daysAgo(4)
    let pushDay = daysAgo(2)
    return fixtureRoutine(
        title: "Autumn strength", goal: "Add 20 lb to the bench", startDate: daysAgo(14),
        durationMinutes: 60,
        blocks: [
            (label: "Accumulation", isDeload: false, days: [
                fixtureDay(
                    weekday: .thursday, focus: "Pull", durationMinutes: 60,
                    completedAt: pullDay,
                    exercises: [
                        prescribed(
                            "barbell-bent-over-row", "Barbell Bent Over Row",
                            sets: 3, reps: "8", load: 185, rest: 120,
                            logged: [
                                set(0, 95, 8, at: pullDay, warmup: true),
                                set(1, 185, 8, at: pullDay),
                                set(2, 185, 8, at: pullDay),
                                set(3, 185, 7, at: pullDay),
                            ]),
                        prescribed(
                            "lat-pulldown", "Lat Pulldown",
                            sets: 3, reps: "12", load: 120, rest: 90,
                            logged: [
                                set(0, 120, 12, at: pullDay),
                                set(1, 120, 12, at: pullDay),
                                set(2, 120, 12, at: pullDay),
                            ]),
                    ]),
                fixtureDay(
                    weekday: .monday, focus: "Push", durationMinutes: 60,
                    completedAt: pushDay,
                    exercises: [
                        prescribed(
                            "barbell-bench-press", "Barbell Bench Press",
                            sets: 3, reps: "5", load: 225, rest: 180,
                            // The effort the plan asked for, so it can be read
                            // beside the reps and load actually logged. Nobody
                            // is asked to rate a set.
                            intensity: IntensityTarget(scale: .rpe, value: "8"),
                            logged: [
                                set(0, 135, 5, at: pushDay, warmup: true),
                                set(1, 225, 5, at: pushDay),
                                set(2, 225, 5, at: pushDay),
                                set(3, 225, 4, at: pushDay),
                                // On screen but never finished.
                                set(4, 225, 0, at: pushDay, completed: false),
                            ]),
                        prescribed(
                            "barbell-curl", "Barbell Curl",
                            sets: 3, reps: "10", load: 65, rest: 60,
                            logged: [
                                set(0, 65, 10, at: pushDay),
                                set(1, 65, 10, at: pushDay),
                                set(2, 65, 10, at: pushDay),
                            ]),
                    ]),
            ]),
            (label: "Accumulation", isDeload: false, days: [
                fixtureDay(
                    weekday: .monday, focus: "Push", durationMinutes: 60,
                    exercises: [
                        prescribed(
                            "barbell-bench-press", "Barbell Bench Press",
                            sets: 3, reps: "5", load: 230, rest: 180)
                    ])
            ]),
        ])
}

func fixtureSnapshot(
    profile: SnapshotProfile? = fixtureProfile(),
    blocks: [(routine: SnapshotRoutine, log: [LoggedSetRecord])]? = nil,
    catalogVersion: Int = 5
) -> TrainingSnapshot {
    let built = blocks ?? [basePlan(), currentPlan()]
    return TrainingSnapshot(
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
        routines: built.map(\.routine),
        log: built.flatMap(\.log).sorted { $0.completedAt < $1.completedAt }
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

extension PlanDocument {

    /// Every training day of the block, in order, for an assertion that does
    /// not care which week a day sits in.
    var everyDay: [PlanDocumentDay] { blocks.flatMap(\.days) }
}

// MARK: - Calling a tool in a test

func makeRunner(
    documents: any TrainingDocuments,
    catalog: (any ExerciseCatalogProviding)? = nil,
    delivery: ToolRunner.DeliveryProspect = .onItsWay
) throws -> ToolRunner {
    ToolRunner(
        documents: documents,
        catalog: try catalog ?? fixtureCatalog(),
        now: { referenceNow },
        delivery: { _ in delivery }
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
