import Testing
import SwiftData
import Foundation
@testable import LiftingPlan

@Suite("Store models")
struct StoreModelTests {

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    @Test("A logged set stores the weight in the unit it was entered")
    func setKeepsEnteredUnit() throws {
        let context = try context()
        context.insert(LoggedSet(setIndex: 0, load: Mass(value: 135, unit: .pounds), reps: 5))
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<LoggedSet>()).first)
        #expect(loaded.load?.value == 135)
        #expect(loaded.load?.unit == .pounds)
    }

    @Test("A bodyweight set has no load rather than a zero load")
    func bodyweightSetHasNoLoad() throws {
        let context = try context()
        context.insert(LoggedSet(setIndex: 0, load: nil, reps: 12))
        try context.saveOrThrow()
        #expect(try #require(try context.fetch(FetchDescriptor<LoggedSet>()).first).load == nil)
    }

    @Test("A planned exercise is keyed by exercise id, not by name")
    func plannedExerciseKeyedByID() throws {
        let context = try context()
        context.insert(PlannedExercise(
            exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
            displayName: "Barbell Bench Press",
            order: 0, targetSets: 3, repRange: "5", restSeconds: 120
        ))
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<PlannedExercise>()).first)
        #expect(loaded.exerciseID == ExerciseID(rawValue: "barbell-bench-press"))
        #expect(loaded.displayName == "Barbell Bench Press")
    }

    @Test("A plan holds weeks in order, and a week can be a deload")
    func planHoldsOrderedWeeks() throws {
        let context = try context()
        let plan = TrainingPlan(title: "Strength block", goal: "Bigger bench", weekCount: 4)
        plan.weeks = [
            TrainingWeek(ordinal: 4, label: "Deload", isDeload: true),
            TrainingWeek(ordinal: 1, label: "Accumulation"),
        ]
        context.insert(plan)
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<TrainingPlan>()).first)
        #expect(loaded.orderedWeeks.map(\.ordinal) == [1, 4])
        #expect(loaded.orderedWeeks.last?.isDeload == true)
        #expect(loaded.orderedWeeks.first?.isDeload == false)
    }

    @Test("Weeks in one plan can prescribe different work — the point of the week layer")
    func weeksCanDiffer() throws {
        let context = try context()
        let heavy = TrainingWeek(ordinal: 1)
        heavy.days = [dayWithBench(sets: 5)]
        let deload = TrainingWeek(ordinal: 2, label: "Deload", isDeload: true)
        deload.days = [dayWithBench(sets: 2)]
        let plan = TrainingPlan(title: "Block", weekCount: 2)
        plan.weeks = [heavy, deload]
        context.insert(plan)
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<TrainingPlan>()).first)
        let setCounts = loaded.orderedWeeks.map { $0.orderedDays.first?.orderedExercises.first?.targetSets }
        #expect(setCounts == [5, 2])
    }

    private func dayWithBench(sets: Int) -> WorkoutDay {
        let exercise = PlannedExercise(
            exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
            displayName: "Barbell Bench Press",
            order: 0, targetSets: sets, repRange: "5", restSeconds: 180
        )
        let day = WorkoutDay(weekday: .monday, focus: "Push")
        day.exercises = [exercise]
        return day
    }

    @Test("Deleting a plan cascades all the way down to logged sets")
    func cascadeDelete() throws {
        let context = try context()
        let exercise = PlannedExercise(
            exerciseID: ExerciseID(rawValue: "push-up"), displayName: "Push Up",
            order: 0, targetSets: 3, repRange: "10", restSeconds: 60
        )
        exercise.loggedSets = [LoggedSet(setIndex: 0, load: nil, reps: 10)]
        let day = WorkoutDay(weekday: .monday, focus: "Push")
        day.exercises = [exercise]
        let week = TrainingWeek(ordinal: 1)
        week.days = [day]
        let plan = TrainingPlan(title: "Block", weekCount: 1)
        plan.weeks = [week]
        context.insert(plan)
        try context.saveOrThrow()

        context.delete(plan)
        try context.saveOrThrow()

        #expect(try context.fetch(FetchDescriptor<TrainingWeek>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<WorkoutDay>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PlannedExercise>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<LoggedSet>()).isEmpty)
    }

    @Test("A plan owns its conversation, which is what makes it project-like")
    func planOwnsConversation() throws {
        let context = try context()
        let plan = TrainingPlan(title: "Block", weekCount: 8)
        plan.messages = [
            PlanMessage(role: .assistant, text: "Built you an 8-week block.", createdAt: .distantPast),
            PlanMessage(role: .user, text: "Make week 4 a deload", createdAt: .distantFuture),
        ]
        context.insert(plan)
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<TrainingPlan>()).first)
        #expect(loaded.orderedMessages.map(\.role) == [.assistant, .user])
        #expect(loaded.orderedMessages.first?.text.contains("8-week") == true)
    }

    @Test("A plan records its training days and its length")
    func planRecordsScheduleAndLength() throws {
        let context = try context()
        context.insert(TrainingPlan(
            title: "Block", goal: "Squat", weekCount: 12,
            weekdays: [.friday, .monday]
        ))
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<TrainingPlan>()).first)
        #expect(loaded.weekCount == 12)
        // `weekdays` is a Set, so compare against a Set — an array literal
        // here does not type-check.
        #expect(loaded.weekdays == Set<Weekday>([.monday, .friday]))
        #expect(loaded.orderedWeekdays == [.monday, .friday])
    }

    /// Round-tripping only. That a *generated* plan is stamped with the version
    /// of the catalog that produced it is behaviour, and lives in
    /// `CatalogVersionStampingTests`, which goes through the production path.
    @Test("A plan's catalog version survives a save and reload")
    func planPersistsCatalogVersion() throws {
        let context = try context()
        context.insert(TrainingPlan(title: "Block", catalogVersion: 3))
        try context.saveOrThrow()
        let loaded = try #require(try context.fetch(FetchDescriptor<TrainingPlan>()).first)
        #expect(loaded.catalogVersion == 3)
    }

    @Test("A profile round-trips its display unit and access tier")
    func profileRoundTrips() throws {
        let context = try context()
        context.insert(UserProfile(
            displayUnit: .kilograms, experience: .advanced,
            equipmentAccess: .dumbbellsOnly, goal: "Bigger bench"
        ))
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(loaded.displayUnit == .kilograms)
        #expect(loaded.experience == .advanced)
        #expect(loaded.equipmentAccess == .dumbbellsOnly)
        #expect(loaded.permittedEquipment.contains(.dumbbell))
        #expect(!loaded.permittedEquipment.contains(.barbell))
    }

    @Test("Every model property is optional or defaulted, as CloudKit requires")
    func cloudKitCompatible() throws {
        // Constructing each model with no arguments proves every property
        // carries a default — the CloudKit requirement that is easiest to
        // violate accidentally and hardest to notice until sync fails.
        let context = try context()
        context.insert(UserProfile())
        context.insert(TrainingPlan())
        context.insert(TrainingWeek())
        context.insert(WorkoutDay())
        context.insert(PlannedExercise())
        context.insert(LoggedSet())
        context.insert(PlanMessage())
        try context.saveOrThrow()
    }
}
