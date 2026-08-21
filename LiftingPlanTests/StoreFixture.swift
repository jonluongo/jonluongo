import Foundation
import SwiftData
import Testing
@testable import LiftingPlan
import LiftingKit

/// A store, and the documents these suites put into one.
///
/// **One builder for every suite.** The old suites each grew their own, so a
/// change to the model meant finding twenty copies of the same four lines —
/// which is part of why twenty-two of them had to be rewritten at once.
enum StoreFixture {

    static let bench = ExerciseID(rawValue: "barbell-bench-press")
    static let row = ExerciseID(rawValue: "barbell-bent-over-row")
    static let squat = ExerciseID(rawValue: "barbell-back-squat")
    static let instant = Date(timeIntervalSince1970: 1_700_000_000)

    static func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    static func catalog() throws -> ExerciseCatalog { try ExerciseCatalog.bundled() }

    /// One prescribed set.
    static func set(
        _ target: Target? = .repetitions(low: 5, high: nil),
        load: Double? = 100, warmup: Bool = false
    ) -> PlanDocumentSet {
        PlanDocumentSet(
            target: target,
            load: load.map { Mass(value: $0, unit: .kilograms) },
            isWarmup: warmup)
    }

    /// One prescribed movement, with `count` identical working sets.
    static func exercise(
        _ id: ExerciseID = bench, sets count: Int = 3, rest: Int? = 180,
        note: String? = nil
    ) -> PlanDocumentExercise {
        PlanDocumentExercise(
            exerciseID: id, displayName: "", restSeconds: rest, coachNote: note,
            sets: Array(repeating: set(), count: count))
    }

    /// A plan of `blocks` blocks with `sessionsPerBlock` sessions in each, every
    /// session prescribing the same movement.
    static func plan(
        blocks: Int = 1, sessionsPerBlock: Int = 1,
        entries: [PlanDocumentEntry] = [.exercise(exercise())],
        id: UUID = UUID()
    ) -> PlanDocument {
        PlanDocument(
            id: id, catalogVersion: 5, generatedAt: instant,
            sessions: (1...blocks).flatMap { block in
                (1...sessionsPerBlock).map { ordinal in
                    PlanDocumentSession(
                        blockOrdinal: block, ordinal: ordinal,
                        focus: "Day \(ordinal)", entries: entries)
                }
            })
    }

    /// Takes a plan in, and hands back the store it landed in.
    static func imported(_ document: PlanDocument) throws -> ModelContext {
        let context = try context()
        try PlanImporter.import(document, into: context, catalog: try catalog())
        return context
    }

    static func sessions(in context: ModelContext) throws -> [Session] {
        try context.fetch(FetchDescriptor<Session>())
            .sorted { ($0.blockOrdinal, $0.ordinal) < ($1.blockOrdinal, $1.ordinal) }
    }
}
