import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

@Suite("Lifter data")
struct LifterDataTests {

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    @Test("Bodyweight is a tracked series, not one mutable number")
    func bodyweightIsASeries() throws {
        let context = try context()
        context.insert(BodyMetric(date: .distantPast, bodyweight: Mass(value: 180, unit: .pounds)))
        context.insert(BodyMetric(date: .distantFuture, bodyweight: Mass(value: 185, unit: .pounds)))
        try context.saveOrThrow()

        let metrics = try context.fetch(FetchDescriptor<BodyMetric>()).sorted { $0.date < $1.date }
        #expect(metrics.count == 2)
        #expect(metrics.first?.bodyweight?.value == 180)
        #expect(metrics.last?.bodyweight?.value == 185)
    }

    @Test("A strength baseline records what the lifter can currently do")
    func baselineRecordsCurrentStrength() throws {
        let context = try context()
        context.insert(StrengthBaseline(
            exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
            load: Mass(value: 185, unit: .pounds), reps: 5
        ))
        try context.saveOrThrow()

        let baseline = try #require(try context.fetch(FetchDescriptor<StrengthBaseline>()).first)
        #expect(baseline.exerciseID == ExerciseID(rawValue: "barbell-bench-press"))
        #expect(baseline.load?.value == 185)
        #expect(baseline.reps == 5)
        // In the unit it was stated in, and nothing derived from it — what an
        // estimated one-rep max makes of 185 × 5 depends on which formula you
        // believe, and this app believes none of them.
        #expect(baseline.load?.unit == .pounds)
    }

    @Test("An avoided pattern makes a constraint enforceable rather than advisory")
    func avoidedPatternsFilter() throws {
        let context = try context()
        let profile = UserProfile()
        profile.avoidedPatterns = [.verticalPress]
        context.insert(profile)
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(loaded.avoidedPatterns.contains(.verticalPress))
        #expect(!loaded.avoidedPatterns.contains(.squat))
    }

    @Test("An avoided exercise is excluded by id")
    func avoidedExercisesFilter() throws {
        let context = try context()
        let profile = UserProfile()
        profile.avoidedExercises = [ExerciseID(rawValue: "barbell-bench-press")]
        context.insert(profile)
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(loaded.avoidedExercises.contains(ExerciseID(rawValue: "barbell-bench-press")))
        #expect(!loaded.avoidedExercises.contains(ExerciseID(rawValue: "push-up")))
    }

    @Test("The new models satisfy CloudKit's defaulted-property requirement")
    func cloudKitCompatible() throws {
        let context = try context()
        context.insert(BodyMetric())
        context.insert(StrengthBaseline())
        try context.saveOrThrow()
    }
}
