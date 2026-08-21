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

// MARK: - The record

/// Building the record these suites ask questions of.
///
/// **One builder, and it is two lists.** The old fixtures assembled a routine of
/// blocks of days keyed by weekday, then a flat log of sets keyed back to it —
/// 445 lines, most of it keeping the two in step. A snapshot is sessions and
/// performances now, each stating its own coordinates, so a fixture is what you
/// want to ask about and nothing else.

func fixtureSet(
    _ target: Target? = .repetitions(low: 5, high: nil),
    load: Double? = 100, warmup: Bool = false, rpe: String? = nil
) -> PlanDocumentSet {
    PlanDocumentSet(
        target: target,
        load: load.map { Mass(value: $0, unit: .kilograms) },
        intensity: rpe.map { IntensityTarget(scale: .rpe, value: $0) },
        isWarmup: warmup)
}

func fixtureExercise(
    _ id: String = "barbell-bench-press", sets: [PlanDocumentSet] = [fixtureSet()],
    rest: Int? = 180, note: String? = nil
) -> PlanDocumentExercise {
    PlanDocumentExercise(
        exerciseID: ExerciseID(rawValue: id), displayName: "",
        restSeconds: rest, coachNote: note, sets: sets)
}

func fixtureSession(
    block: Int = 1, ordinal: Int = 1, focus: String = "Push",
    icon: SessionIcon? = nil, entries: [PlanDocumentEntry] = [.exercise(fixtureExercise())],
    finished: Date? = nil
) -> SnapshotSession {
    SnapshotSession(
        prescription: PlanDocumentSession(
            blockOrdinal: block, ordinal: ordinal, focus: focus, icon: icon, entries: entries),
        finishedAt: finished,
        generatedAt: daysAgo(40))
}

func fixturePerformedSet(
    index: Int = 0, load: Double? = 100, reps: Int? = 5,
    seconds: Int? = nil, distance: Distance? = nil,
    warmup: Bool = false, at when: Date = daysAgo(2)
) -> SnapshotPerformedSet {
    SnapshotPerformedSet(
        setIndex: index, isWarmup: warmup,
        load: load.map { Mass(value: $0, unit: .kilograms) },
        reps: reps, durationSeconds: seconds, distance: distance, completedAt: when)
}

func fixturePerformance(
    _ id: String = "barbell-bench-press", block: Int? = 1, ordinal: Int? = 1,
    at when: Date = daysAgo(2), source: PerformanceSource = .logged,
    note: String? = nil, sets: [SnapshotPerformedSet] = [fixturePerformedSet()]
) -> SnapshotPerformedExercise {
    SnapshotPerformedExercise(
        exerciseID: ExerciseID(rawValue: id), occurredAt: when, source: source,
        blockOrdinal: block, sessionOrdinal: ordinal, userNote: note, sets: sets)
}

func fixtureSnapshot(
    sessions: [SnapshotSession] = [fixtureSession()],
    performances: [SnapshotPerformedExercise] = [fixturePerformance()],
    exportedAt: Date = daysAgo(1), catalogVersion: Int = 5
) -> TrainingSnapshot {
    TrainingSnapshot(
        exportedAt: exportedAt, catalogVersion: catalogVersion,
        sessions: sessions, performances: performances)
}

// MARK: - The folder, in memory

/// A stand-in for the shared folder, so a tool can be tested without a disk.
///
/// **It keeps what was written**, because most of what these suites assert is
/// what the coach's call actually put on the wire — a plan he cannot read back
/// is a plan he cannot check.
final class InMemoryDocuments: TrainingDocuments, @unchecked Sendable {

    var snapshot: TrainingSnapshot?
    var writtenPlan: PlanDocument?
    /// What `write_plan` last put on the wire. Named for what a suite asks it.
    var lastWrittenPlan: PlanDocument? { writtenPlan }
    var notes: [NoteFile: String] = [:]
    /// Every version kept before an edit, oldest first.
    var keptCopies: [(note: NoteFile, text: String)] = []
    /// Set to make a write fail, for the paths that report one.
    var writeFailure: (any Error)?
    /// Set to make reading the record fail, which is a different thing from
    /// there being no record: one is a folder nobody has written to yet, and the
    /// other is a folder that cannot be reached. A tool that reported them the
    /// same way would tell a coach the user has never trained.
    var readFailure: (any Error)?

    init(snapshot: TrainingSnapshot? = nil, notes: [NoteFile: String] = [:]) {
        self.snapshot = snapshot
        self.notes = notes
    }

    func readSnapshot() throws -> TrainingSnapshot? {
        if let readFailure { throw readFailure }
        return snapshot
    }

    func writePlan(_ plan: PlanDocument) throws {
        if let writeFailure { throw writeFailure }
        writtenPlan = plan
    }

    func readNote(_ note: NoteFile) throws -> String? { notes[note] }

    func writeNote(_ text: String, as note: NoteFile) throws {
        if let writeFailure { throw writeFailure }
        notes[note] = text
    }

    func keepCopy(of text: String, as note: NoteFile) throws {
        keptCopies.append((note: note, text: text))
    }

    var snapshotLocation: String { "in memory" }
    var planLocation: String { "in memory" }
}

/// A stand-in failure for the folder being unreachable.
enum TransportFailure: Error, LocalizedError {
    case unreachable
    var errorDescription: String? { "The shared folder could not be read." }
}

/// A runner over an in-memory folder, with the clock stopped.
///
/// The clock is fixed because a report that states how old the record is cannot
/// be asserted against a moving `now`.
func makeRunner(
    documents: any TrainingDocuments,
    catalog: (any ExerciseCatalogProviding)? = nil,
    catalogVersion: Int = 5
) throws -> ToolRunner {
    ToolRunner(
        documents: documents,
        catalog: try catalog ?? fixtureCatalog(version: catalogVersion),
        now: { referenceNow },
        delivery: { _ in .onItsWay })
}

// MARK: - Reading an outcome

/// What a suite asks of a tool's answer.
///
/// **Both are optional and exactly one is ever non-nil**, which is the assertion
/// most of these suites are really making: a tool that fails must not also
/// report, because an empty report reads as a user with no history rather than
/// as a question that could not be answered.
extension ToolOutcome {

    var report: JSONValue? {
        if case .report(let value) = self { return value }
        return nil
    }

    var failureMessage: String? {
        if case .failure(let message) = self { return message }
        return nil
    }
}
