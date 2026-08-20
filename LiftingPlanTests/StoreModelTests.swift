import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

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
        let plan = TrainingPlan(title: "Strength block", goal: "Bigger bench")
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
        let plan = TrainingPlan(title: "Block")
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
        let plan = TrainingPlan(title: "Block")
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

    @Test("A plan records the days it trains on")
    func planRecordsSchedule() throws {
        let context = try context()
        context.insert(TrainingPlan(
            title: "Block", goal: "Squat", weekdays: [.friday, .monday]
        ))
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<TrainingPlan>()).first)
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

    @Test("A profile round-trips its display unit and the equipment he owns")
    func profileRoundTrips() throws {
        let context = try context()
        context.insert(UserProfile(
            displayUnit: .kilograms, experience: .advanced,
            ownedEquipment: [.dumbbell, .plate], goal: "Bigger bench"
        ))
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(loaded.displayUnit == .kilograms)
        #expect(loaded.experience == .advanced)
        #expect(loaded.ownedEquipment.map(Set.init) == [.dumbbell, .plate])
        #expect(loaded.permittedEquipment?.contains(.dumbbell) == true)
        #expect(loaded.permittedEquipment?.contains(.barbell) == false)
    }

    @Test("A gym no tier describes round-trips, including a type this build does not know")
    func profileRoundTripsAnOpenGym() throws {
        let context = try context()
        let unknown = EquipmentType(rawValue: "reverse hyper")
        context.insert(UserProfile(ownedEquipment: [.barbell, .band, unknown]))
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(loaded.ownedEquipment.map(Set.init) == [.barbell, .band, unknown])
        #expect(loaded.permittedEquipment?.contains(.cable) == false)
    }

    @Test("A lifter who owns nothing is not a lifter nobody has asked")
    func owningNothingIsNotUnknown() throws {
        let context = try context()
        context.insert(UserProfile(ownedEquipment: []))
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(loaded.ownedEquipment == [])
        #expect(loaded.permittedEquipment == [.bodyweight], "he can still do a push-up")
    }

    @Test("A profile round-trips the schedule the lifter stated in setup")
    func profileRoundTripsStatedSchedule() throws {
        let context = try context()
        context.insert(UserProfile(
            preferredDurationMinutes: 75
        ))
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(loaded.preferredDurationMinutes == 75)
    }

    @Test("A profile that has said nothing about its schedule stores nothing")
    func profileStatesNoScheduleByDefault() throws {
        let context = try context()
        context.insert(UserProfile())
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(loaded.preferredDurationMinutes == nil)
    }

    @Test("A profile nobody has told anything stores nothing, not a default gym or level")
    func profileStatesNothingByDefault() throws {
        // Nothing asks the lifter these questions any more, so the untouched
        // record has to be able to say "not known" rather than defaulting to a
        // claim about him.
        let context = try context()
        context.insert(UserProfile())
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(loaded.experience == nil)
        #expect(loaded.ownedEquipment == nil)
        #expect(loaded.permittedEquipment == nil)
        #expect(loaded.goal.isEmpty)
        #expect(loaded.appliedProfileUpdateID == nil)
    }

    @Test("Defaults state no training opinion, only 'not specified'")
    func defaultsAreNeutral() throws {
        // CloudKit requires a default on every property, so these cannot be
        // removed — but a default is not a licence to prescribe. Anything a
        // plan does not set must read as unstated, never as Mon/Wed/Fri,
        // 8 weeks, 45 minutes, or 90 seconds of rest.
        let context = try context()
        let plan = TrainingPlan()
        let day = WorkoutDay()
        let exercise = PlannedExercise()
        context.insert(plan)
        context.insert(day)
        context.insert(exercise)
        try context.saveOrThrow()

        #expect(plan.weekdays.isEmpty)
        #expect(plan.durationMinutes == nil)
        #expect(day.durationMinutes == nil)
        #expect(day.focus == "")
        #expect(exercise.restSeconds == nil)
        #expect(exercise.targetSets == 0)
        #expect(exercise.repRange == "")
    }

    @Test("Every model property is optional or defaulted, as CloudKit requires")
    func cloudKitCompatible() throws {
        // Constructing each model with no arguments proves every property
        // carries a default — the CloudKit requirement that is easiest to
        // violate accidentally and hardest to notice until sync fails. Every
        // model in the schema, not most of them: the three newest were the
        // three this test did not reach.
        let context = try context()
        context.insert(UserProfile())
        context.insert(TrainingPlan())
        context.insert(TrainingWeek())
        context.insert(WorkoutDay())
        context.insert(PlannedExercise())
        context.insert(PrescribedSet())
        context.insert(LoggedSet())
        context.insert(BodyMetric())
        context.insert(StrengthBaseline())
        try context.saveOrThrow()
    }

    @Test("A set records reps or a hold, and states no hold when it was not timed")
    func loggedSetDurationIsAbsentUntilRecorded() throws {
        let context = try context()
        let counted = LoggedSet(reps: 5)
        let held = LoggedSet(durationSeconds: 34)
        context.insert(counted)
        context.insert(held)
        try context.saveOrThrow()

        #expect(counted.durationSeconds == nil, "not timed is not zero seconds")
        #expect(held.durationSeconds == 34)
        #expect(held.reps == 0)
    }
}
