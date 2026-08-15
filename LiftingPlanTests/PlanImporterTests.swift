import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

@Suite("Plan importer")
struct PlanImporterTests {

    // MARK: - Fixtures

    /// The real bundled catalog. The one thing the import checks is that an
    /// `ExerciseID` exists, so checking it against a fixture would test the
    /// fixture rather than the guard that matters.
    private func catalog() throws -> ExerciseCatalog {
        try ExerciseCatalog.bundled()
    }

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    private static let benchPress = ExerciseID(rawValue: "barbell-bench-press")
    private static let squat = ExerciseID(rawValue: "barbell-squat")
    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)

    private func exercise(
        exerciseID: ExerciseID = PlanImporterTests.benchPress,
        sets: Int = 3,
        repRange: String = "5",
        restSeconds: Int? = 180,
        suggestedLoad: Mass? = Mass(value: 225, unit: .pounds)
    ) -> PlanDocumentExercise {
        PlanDocumentExercise(
            exerciseID: exerciseID, displayName: "Barbell Bench Press",
            sets: sets, repRange: repRange, restSeconds: restSeconds,
            suggestedLoad: suggestedLoad, tempo: "3-0-1-0", notes: "Pause the last rep"
        )
    }

    private func document(
        id: UUID = UUID(),
        title: String = "Strength block",
        days: [PlanDocumentDay]? = nil,
        exercises: [PlanDocumentExercise]? = nil
    ) -> PlanDocument {
        PlanDocument(
            id: id, catalogVersion: 5, generatedAt: Self.instant,
            title: title, goal: "Bigger bench", weekCount: 4,
            durationMinutes: 60, notes: "Keep pressing volume moderate.",
            days: days ?? [
                PlanDocumentDay(
                    weekday: .monday, focus: "Push", durationMinutes: 60,
                    exercises: exercises ?? [exercise()]
                ),
                PlanDocumentDay(
                    weekday: .thursday, focus: "Legs", durationMinutes: 75,
                    exercises: [exercise(exerciseID: Self.squat, sets: 5, repRange: "3")]
                ),
            ]
        )
    }

    private func plans(in context: ModelContext) throws -> [TrainingPlan] {
        try context.fetch(FetchDescriptor<TrainingPlan>(sortBy: [SortDescriptor(\.startDate)]))
    }

    private func firstExercise(of plan: TrainingPlan) throws -> PlannedExercise {
        let week = try #require(plan.orderedWeeks.first)
        let day = try #require(week.orderedDays.first)
        return try #require(day.orderedExercises.first)
    }

    // MARK: - Every value arrives exactly as prescribed

    @Test("A valid plan imports with its block-level facts intact")
    func importsBlockFacts() throws {
        let context = try context()
        let plan = try PlanImporter.import(
            document(), into: context, catalog: try catalog(), importedAt: Self.instant
        )

        #expect(plan.title == "Strength block")
        #expect(plan.goal == "Bigger bench")
        #expect(plan.weekCount == 4)
        #expect(plan.durationMinutes == 60)
        #expect(plan.startDate == Self.instant)
        #expect(plan.completedAt == nil)
        // The stamp records which generation of the catalog the *document's*
        // exercise IDs were chosen from, which the document states itself.
        #expect(plan.catalogVersion == 5)
        // Derived from the days the plan actually trains, not from anything
        // the lifter said he preferred.
        #expect(plan.orderedWeekdays == [.monday, .thursday])
        #expect(try plans(in: context).count == 1)
    }

    @Test("Days and exercises import in the order the document gave them")
    func importsInOrder() throws {
        let context = try context()
        let plan = try PlanImporter.import(
            document(exercises: [
                exercise(exerciseID: Self.benchPress),
                exercise(exerciseID: ExerciseID(rawValue: "barbell-bent-over-row")),
            ]),
            into: context, catalog: try catalog()
        )

        let week = try #require(plan.orderedWeeks.first)
        #expect(week.ordinal == 1)
        #expect(week.days?.count == 2)
        let monday = try #require(week.orderedDays.first)
        #expect(monday.weekday == .monday)
        #expect(monday.focus == "Push")
        #expect(monday.durationMinutes == 60)
        #expect(monday.orderedExercises.map(\.order) == [0, 1])
        #expect(monday.orderedExercises.map(\.exerciseID) == [
            Self.benchPress, ExerciseID(rawValue: "barbell-bent-over-row"),
        ])
    }

    @Test("An extreme prescription is imported untouched")
    func extremePrescriptionSurvivesImport() throws {
        // 12 sets at 900 seconds of rest is a real prescription. Anything that
        // capped it would be the app overruling the coach, and the lifter would
        // be handed a plan nobody wrote.
        let context = try context()
        let plan = try PlanImporter.import(
            document(exercises: [exercise(sets: 12, restSeconds: 900)]),
            into: context, catalog: try catalog()
        )
        let imported = try firstExercise(of: plan)

        #expect(imported.targetSets == 12)
        #expect(imported.restSeconds == 900)
    }

    @Test("An empty rep range stays empty rather than being filled in")
    func emptyRepRangeStaysEmpty() throws {
        let context = try context()
        let plan = try PlanImporter.import(
            document(exercises: [exercise(repRange: "")]),
            into: context, catalog: try catalog()
        )
        let imported = try firstExercise(of: plan)

        #expect(imported.repRange == "")
        #expect(RepRange(imported.repRange).isEmpty)
    }

    @Test("An unprescribed rest and an unstated load stay absent, never zero")
    func absentValuesStayAbsent() throws {
        let context = try context()
        let plan = try PlanImporter.import(
            document(exercises: [exercise(restSeconds: nil, suggestedLoad: nil)]),
            into: context, catalog: try catalog()
        )
        let imported = try firstExercise(of: plan)

        #expect(imported.restSeconds == nil)
        #expect(imported.suggestedLoad == nil)
    }

    @Test("A suggested load is imported in the unit it was written in")
    func suggestedLoadKeepsItsUnit() throws {
        let context = try context()
        let plan = try PlanImporter.import(
            document(exercises: [exercise(suggestedLoad: Mass(value: 225, unit: .pounds))]),
            into: context, catalog: try catalog()
        )
        let load = try #require(try firstExercise(of: plan).suggestedLoad)

        #expect(load == Mass(value: 225, unit: .pounds))
        #expect(load != Mass(value: 225, unit: .pounds).converted(to: .kilograms))
    }

    @Test("Display name, tempo, and notes are carried through for display")
    func carriesDisplayFields() throws {
        let context = try context()
        let plan = try PlanImporter.import(document(), into: context, catalog: try catalog())
        let imported = try firstExercise(of: plan)

        #expect(imported.displayName == "Barbell Bench Press")
        #expect(imported.tempo == "3-0-1-0")
        #expect(imported.notes == "Pause the last rep")
    }

    @Test("A rest day imports as a day with no exercises rather than being dropped")
    func restDayImports() throws {
        let context = try context()
        let plan = try PlanImporter.import(
            document(days: [
                PlanDocumentDay(
                    weekday: .sunday, focus: "Rest", durationMinutes: nil, exercises: []
                )
            ]),
            into: context, catalog: try catalog()
        )

        let day = try #require(plan.orderedWeeks.first?.orderedDays.first)
        #expect(day.weekday == .sunday)
        #expect(day.orderedExercises.isEmpty)
    }

    // MARK: - The one thing the import checks

    @Test("An unknown exercise ID throws an error naming that exact ID")
    func unknownExerciseThrowsNamingTheID() throws {
        let context = try context()
        let unknown = ExerciseID(rawValue: "zercher-good-morning")
        #expect(try catalog().exercise(id: unknown) == nil)

        #expect(throws: PlanImportError.unknownExercise(unknown)) {
            try PlanImporter.import(
                document(exercises: [exercise(exerciseID: unknown)]),
                into: context, catalog: try catalog()
            )
        }
    }

    @Test("The unknown-exercise error puts the offending ID in its message")
    func errorMessageNamesTheID() throws {
        let unknown = ExerciseID(rawValue: "zercher-good-morning")
        let message = try #require(PlanImportError.unknownExercise(unknown).errorDescription)
        #expect(message.contains("zercher-good-morning"))
    }

    @Test("A document with one unknown ID imports nothing at all")
    func unknownExerciseImportsNothing() throws {
        let context = try context()
        let unknown = ExerciseID(rawValue: "zercher-good-morning")

        // The first day is entirely valid; only the second day is bad. A
        // partial import that silently dropped the bad movement — or that kept
        // the good day — would be worse than a clean failure.
        #expect(throws: (any Error).self) {
            try PlanImporter.import(
                document(days: [
                    PlanDocumentDay(
                        weekday: .monday, focus: "Push", durationMinutes: 60,
                        exercises: [exercise()]
                    ),
                    PlanDocumentDay(
                        weekday: .thursday, focus: "Legs", durationMinutes: 60,
                        exercises: [exercise(exerciseID: unknown)]
                    ),
                ]),
                into: context, catalog: try catalog()
            )
        }

        #expect(try plans(in: context).isEmpty)
        #expect(try context.fetch(FetchDescriptor<WorkoutDay>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PlannedExercise>()).isEmpty)
    }

    @Test("A failed import leaves an existing plan exactly as it was")
    func failedImportLeavesTheStoreUnchanged() throws {
        let context = try context()
        let first = try PlanImporter.import(
            document(title: "First block"), into: context, catalog: try catalog()
        )

        #expect(throws: (any Error).self) {
            try PlanImporter.import(
                document(exercises: [
                    exercise(exerciseID: ExerciseID(rawValue: "zercher-good-morning"))
                ]),
                into: context, catalog: try catalog()
            )
        }

        #expect(try plans(in: context).count == 1)
        #expect(try plans(in: context).first?.title == "First block")
        // Not closed out either: a failed import supersedes nothing.
        #expect(first.completedAt == nil)
    }

    // MARK: - Importing twice

    @Test("Importing the same document twice does not duplicate it")
    func reimportingDoesNotDuplicate() throws {
        let context = try context()
        let document = document()

        let first = try PlanImporter.import(document, into: context, catalog: try catalog())
        let second = try PlanImporter.import(document, into: context, catalog: try catalog())

        #expect(try plans(in: context).count == 1)
        #expect(first === second)
        #expect(second.completedAt == nil)
    }

    @Test("Two documents with different identities both import")
    func differentDocumentsBothImport() throws {
        let context = try context()
        try PlanImporter.import(
            document(title: "First block"), into: context, catalog: try catalog(),
            importedAt: Self.instant
        )
        try PlanImporter.import(
            document(title: "Second block"), into: context, catalog: try catalog(),
            importedAt: Self.instant.addingTimeInterval(86_400)
        )

        #expect(try plans(in: context).map(\.title) == ["First block", "Second block"])
    }

    // MARK: - Imports never destroy

    @Test("A new plan supersedes the old one; the old plan and its sets survive")
    func importSupersedesRatherThanOverwrites() throws {
        let context = try context()
        let first = try PlanImporter.import(
            document(title: "First block"), into: context, catalog: try catalog(),
            importedAt: Self.instant
        )

        // The lifter trains a session against the first plan.
        let logged = try firstExercise(of: first)
        logged.loggedSets = [
            LoggedSet(
                setIndex: 0, load: Mass(value: 225, unit: .pounds), reps: 5,
                rpe: 8.5, isCompleted: true
            )
        ]
        try context.saveOrThrow()

        let second = try PlanImporter.import(
            document(title: "Second block"), into: context, catalog: try catalog(),
            importedAt: Self.instant.addingTimeInterval(86_400)
        )

        // Both plans exist. Nothing was overwritten, nothing was deleted.
        let stored = try plans(in: context)
        #expect(stored.count == 2)
        #expect(stored.map(\.title) == ["First block", "Second block"])

        // Every set logged against the superseded plan is still there, still
        // attached to the exercise it was logged against.
        let sets = try context.fetch(FetchDescriptor<LoggedSet>())
        #expect(sets.count == 1)
        #expect(sets.first?.reps == 5)
        #expect(sets.first?.load == Mass(value: 225, unit: .pounds))
        #expect(sets.first?.exercise?.exerciseID == Self.benchPress)
        #expect(try firstExercise(of: first).completedWorkingSets.count == 1)

        // The superseded block is closed at the moment the new one begins, so
        // the current block is unambiguous without deleting anything.
        #expect(first.completedAt == Self.instant.addingTimeInterval(86_400))
        #expect(second.completedAt == nil)
    }

    @Test("Superseding does not disturb a block the lifter had already finished")
    func alreadyFinishedPlanKeepsItsOwnCompletionDate() throws {
        let context = try context()
        let first = try PlanImporter.import(
            document(title: "First block"), into: context, catalog: try catalog(),
            importedAt: Self.instant
        )
        first.completedAt = Self.instant.addingTimeInterval(3_600)
        try context.saveOrThrow()

        try PlanImporter.import(
            document(title: "Second block"), into: context, catalog: try catalog(),
            importedAt: Self.instant.addingTimeInterval(86_400)
        )

        #expect(first.completedAt == Self.instant.addingTimeInterval(3_600))
    }

    @Test("An imported plan is written to the store, not just returned")
    func importIsPersisted() throws {
        let context = try context()
        try PlanImporter.import(document(), into: context, catalog: try catalog())
        #expect(!context.hasChanges)
        #expect(try plans(in: context).count == 1)
    }
}
