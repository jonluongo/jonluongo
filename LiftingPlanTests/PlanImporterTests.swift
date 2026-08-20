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
            title: title, goal: "Bigger bench",
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
        // One week was stated, so the block runs one week. The count is the
        // weeks that arrived, not a number the document was taken on trust for.
        #expect(plan.weekCount == 1)
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

    // MARK: - A block is more than one week

    /// One week of the block at a stated load, so eight of them are eight
    /// genuinely different weeks rather than the same week eight times.
    private func week(
        _ label: String?, load: Double, isDeload: Bool = false
    ) -> PlanDocumentWeek {
        PlanDocumentWeek(
            label: label, isDeload: isDeload,
            days: [PlanDocumentDay(
                weekday: .monday, focus: "Lower",
                exercises: [exercise(suggestedLoad: Mass(value: load, unit: .pounds))]
            )]
        )
    }

    private func block(_ weeks: [PlanDocumentWeek], id: UUID = UUID()) -> PlanDocument {
        PlanDocument(
            id: id, catalogVersion: 5, generatedAt: Self.instant,
            title: "Eight-week block", goal: "Bigger bench", weeks: weeks
        )
    }

    @Test("An eight-week block imports as eight weeks, each with its own days")
    func eightWeekBlockImportsAsEightWeeks() throws {
        // The exact case that used to lose seven weeks in silence.
        let context = try context()
        let weeks = (0..<8).map { week("Week \($0 + 1)", load: 275 + Double($0) * 10) }

        let plan = try PlanImporter.import(
            block(weeks), into: context, catalog: try catalog(), importedAt: Self.instant
        )

        #expect(plan.orderedWeeks.count == 8)
        #expect(plan.weekCount == 8)
        #expect(plan.orderedWeeks.map(\.ordinal) == Array(1...8))
        #expect(plan.orderedWeeks.allSatisfy { $0.orderedDays.count == 1 })

        let loads: [Double?] = plan.orderedWeeks.map {
            $0.orderedDays.first?.orderedExercises.first?.suggestedLoad?.value
        }
        let expected: [Double?] = (0..<8).map { 275 + Double($0) * 10 }
        #expect(loads == expected, "each week keeps the load it was prescribed")
    }

    @Test("A deload week imports with its flag and its label intact")
    func deloadWeekImports() throws {
        let context = try context()
        let plan = try PlanImporter.import(
            block([
                week("Accumulation", load: 315),
                week("Back off", load: 225, isDeload: true),
            ]),
            into: context, catalog: try catalog()
        )

        #expect(plan.orderedWeeks.map(\.isDeload) == [false, true])
        #expect(plan.orderedWeeks.map(\.label) == ["Accumulation", "Back off"])
    }

    @Test("A week the plan did not name arrives unnamed rather than called 'Week 1'")
    func unnamedWeekStaysUnnamed() throws {
        let context = try context()
        let plan = try PlanImporter.import(
            block([week(nil, load: 275)]), into: context, catalog: try catalog()
        )

        #expect(plan.orderedWeeks.first?.label == "")
    }

    @Test("The block trains every day any of its weeks trains")
    func trainingDaysCoverEveryWeek() throws {
        let context = try context()
        let thursday = PlanDocumentWeek(days: [
            PlanDocumentDay(weekday: .thursday, exercises: [exercise()])
        ])
        let plan = try PlanImporter.import(
            block([week("Accumulation", load: 275), thursday]),
            into: context, catalog: try catalog()
        )

        #expect(plan.orderedWeekdays == [.monday, .thursday])
    }

    @Test("A multi-week block survives being written to the store and read back")
    func multiWeekBlockPersists() throws {
        let context = try context()
        try PlanImporter.import(
            block((0..<8).map { week("Week \($0 + 1)", load: 275) }),
            into: context, catalog: try catalog()
        )

        let stored = try #require(try plans(in: context).first)
        #expect(stored.orderedWeeks.count == 8)
        #expect(try context.fetch(FetchDescriptor<TrainingWeek>()).count == 8)
        // Eight weeks of one day each, not one week of eight days.
        #expect(try context.fetch(FetchDescriptor<WorkoutDay>()).count == 8)
    }

    @Test("The plan screen opens on the first week that still has work in it")
    func weekSelectionFollowsRealMultiWeekData() throws {
        // The display side derives the current week from what has been logged.
        // Real multi-week data has to satisfy it, not just hand-built weeks.
        let context = try context()
        let plan = try PlanImporter.import(
            block([
                week("Accumulation", load: 275),
                week("Intensification", load: 295),
                week("Deload", load: 205, isDeload: true),
            ]),
            into: context, catalog: try catalog()
        )

        #expect(BlockSelection.currentWeekOrdinal(in: plan.orderedWeeks) == 1)

        // Finish every session of week 1.
        for day in plan.orderedWeeks[0].orderedDays { day.completedAt = Self.instant }
        try context.saveOrThrow()

        #expect(BlockSelection.currentWeekOrdinal(in: plan.orderedWeeks) == 2)
        #expect(plan.orderedWeeks.map(BlockSelection.title(for:))
            == ["Block 1 · Accumulation", "Block 2 · Intensification", "Block 3 · Deload"])
    }

    @Test("A single-week document in the older shape still imports")
    func olderSingleWeekDocumentStillImports() throws {
        let json = """
        {
          "version": 1, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "title": "Strength block", "weekCount": 1,
          "days": [{
            "weekday": 2, "focus": "Push",
            "exercises": [{
              "exerciseID": "barbell-bench-press",
              "displayName": "Barbell Bench Press", "sets": 5
            }]
          }]
        }
        """
        let document = try PlanDocument.makeDecoder()
            .decode(PlanDocument.self, from: Data(json.utf8))
        let context = try context()

        let plan = try PlanImporter.import(document, into: context, catalog: try catalog())

        #expect(plan.title == "Strength block")
        #expect(plan.orderedWeeks.count == 1)
        #expect(plan.orderedWeeks.first?.ordinal == 1)
        #expect(plan.orderedWeeks.first?.label == "")
        #expect(plan.orderedWeeks.first?.orderedDays.map(\.weekday) == [.monday])
        #expect(try firstExercise(of: plan).targetSets == 5)
    }

    @Test("An unknown exercise in a later week fails the whole block")
    func unknownExerciseInALaterWeekImportsNothing() throws {
        let context = try context()
        let bad = PlanDocumentWeek(days: [
            PlanDocumentDay(
                weekday: .monday,
                exercises: [exercise(exerciseID: ExerciseID(rawValue: "zercher-good-morning"))]
            )
        ])

        #expect(throws: (any Error).self) {
            try PlanImporter.import(
                block([week("Accumulation", load: 275), bad]),
                into: context, catalog: try catalog()
            )
        }

        #expect(try plans(in: context).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TrainingWeek>()).isEmpty)
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

    // MARK: - The routine grows a block at a time

    /// A routine of `weeks` blocks under one identity, each block one Monday
    /// push session, so a merge can be watched block by block.
    private func routine(id: UUID, blocks: Int, load: Double = 225) -> PlanDocument {
        PlanDocument(
            id: id, catalogVersion: 5, generatedAt: Self.instant, title: "Autumn strength",
            weeks: (1...blocks).map { ordinal in
                PlanDocumentWeek(label: "Block \(ordinal)", days: [
                    PlanDocumentDay(
                        weekday: .monday, focus: "Push",
                        exercises: [exercise(suggestedLoad: Mass(value: load, unit: .pounds))])
                ])
            })
    }

    @Test("Next week's block lands on the routine it belongs to, not beside it")
    func aLaterBlockIsAppended() throws {
        let context = try context()
        let id = UUID()
        let first = try PlanImporter.import(
            routine(id: id, blocks: 1), into: context, catalog: try catalog())
        let grown = try PlanImporter.import(
            routine(id: id, blocks: 2), into: context, catalog: try catalog())

        #expect(try plans(in: context).count == 1)
        #expect(first === grown)
        #expect(grown.orderedWeeks.map(\.ordinal) == [1, 2])
        #expect(grown.orderedWeeks.map(\.label) == ["Block 1", "Block 2"])
    }

    @Test("A block he has not touched is the coach's to rewrite")
    func anUntrainedBlockIsReplaced() throws {
        let context = try context()
        let id = UUID()
        try PlanImporter.import(routine(id: id, blocks: 1), into: context, catalog: try catalog())
        let revised = try PlanImporter.import(
            routine(id: id, blocks: 1, load: 245), into: context, catalog: try catalog())

        let exercise = try firstExercise(of: revised)
        #expect(exercise.suggestedLoad == Mass(value: 245, unit: .pounds))
        #expect(revised.orderedWeeks.count == 1)
    }

    @Test("A block with a set ticked against it cannot be rewritten")
    func aTrainedBlockIsRefused() throws {
        let context = try context()
        let id = UUID()
        let plan = try PlanImporter.import(
            routine(id: id, blocks: 1), into: context, catalog: try catalog())
        let exercise = try firstExercise(of: plan)
        let set = LoggedSet(
            setIndex: 0, load: Mass(value: 225, unit: .pounds), reps: 5, isCompleted: true)
        context.insert(set)
        set.exercise = exercise

        #expect(throws: PlanImportError.trainedBlockChanged(1)) {
            try PlanImporter.import(
                routine(id: id, blocks: 1, load: 245), into: context, catalog: try catalog())
        }
        // Refused whole: the load he trained against is still what it was.
        #expect(try firstExercise(of: plan).suggestedLoad == Mass(value: 225, unit: .pounds))
    }

    @Test("A trained block is no obstacle to the block after it arriving")
    func aLaterBlockLandsBesideATrainedOne() throws {
        let context = try context()
        let id = UUID()
        let plan = try PlanImporter.import(
            routine(id: id, blocks: 1), into: context, catalog: try catalog())
        let set = LoggedSet(setIndex: 0, reps: 5, isCompleted: true)
        context.insert(set)
        set.exercise = try firstExercise(of: plan)

        let grown = try PlanImporter.import(
            routine(id: id, blocks: 2), into: context, catalog: try catalog())

        #expect(grown.orderedWeeks.count == 2)
        #expect(try firstExercise(of: grown).loggedSets?.count == 1)
    }

    @Test("A block the coach dropped goes, as long as nothing was logged in it")
    func anUntrainedBlockIsRemoved() throws {
        let context = try context()
        let id = UUID()
        try PlanImporter.import(routine(id: id, blocks: 3), into: context, catalog: try catalog())
        let shrunk = try PlanImporter.import(
            routine(id: id, blocks: 2), into: context, catalog: try catalog())

        #expect(shrunk.orderedWeeks.map(\.ordinal) == [1, 2])
    }

    @Test("The same document arriving again changes nothing and says so")
    func anUnchangedDocumentIsNotAChange() throws {
        let context = try context()
        let id = UUID()
        let document = routine(id: id, blocks: 2)
        let plan = try PlanImporter.import(document, into: context, catalog: try catalog())
        let set = LoggedSet(setIndex: 0, reps: 5, isCompleted: true)
        context.insert(set)
        set.exercise = try firstExercise(of: plan)

        #expect(try !PlanImporter.wouldChange(document, in: context))
        try PlanImporter.import(document, into: context, catalog: try catalog())

        #expect(plan.orderedWeeks.count == 2)
        #expect(try firstExercise(of: plan).loggedSets?.count == 1)
    }

    @Test("A routine that grows is running again, whatever superseded it")
    func aGrownRoutineReopens() throws {
        let context = try context()
        let id = UUID()
        let plan = try PlanImporter.import(
            routine(id: id, blocks: 1), into: context, catalog: try catalog())
        plan.completedAt = Self.instant

        try PlanImporter.import(routine(id: id, blocks: 2), into: context, catalog: try catalog())

        #expect(plan.completedAt == nil)
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
                isCompleted: true
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
