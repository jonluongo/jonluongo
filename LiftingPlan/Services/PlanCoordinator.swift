import Foundation
import SwiftData

/// Orchestrates plan generation: gathers recent performance, asks the generator
/// for a plan, and persists it. Kept separate from views so the flow is obvious.
///
/// Training days and session length are inputs here rather than being read off
/// `UserProfile`, because they now belong to the `TrainingPlan` being created,
/// not to the lifter's standing identity — a later block can train a different
/// split without touching the profile at all.
@MainActor
enum PlanCoordinator {

    /// Generate a new plan for `weekdays`/`durationMinutes` and store it.
    /// Existing plans feed the progression summary so intensity keeps climbing.
    /// Throws `PersistenceError` if the save fails — callers must surface it.
    @discardableResult
    static func generateAndStore(
        profile: UserProfile,
        weekdays: Set<Weekday>,
        durationMinutes: Int,
        generator: PlanGenerator,
        context: ModelContext,
        existingPlans: [TrainingPlan]
    ) async throws -> TrainingPlan {
        let histories = PerformanceHistory.histories(from: existingPlans)
        let summary = ProgressionEngine.performanceSummary(from: histories)

        let result = await generator.generatePlan(
            profile: profile,
            weekdays: weekdays,
            durationMinutes: durationMinutes,
            performanceSummary: summary.isEmpty ? nil : summary
        )

        let plan = result.blueprint.makeWorkoutPlan(
            goal: profile.goal,
            durationMinutes: durationMinutes,
            wasModelGenerated: result.usedModel
        )
        plan.weekdays = weekdays
        context.insert(plan)
        try context.saveOrThrow()
        return plan
    }
}
