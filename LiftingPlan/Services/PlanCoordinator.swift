import Foundation
import SwiftData

/// Orchestrates plan generation: gathers recent performance, asks the generator
/// for a plan, and persists it. Kept separate from views so the flow is obvious.
@MainActor
enum PlanCoordinator {

    /// Generate a new weekly plan from the current preferences and store it.
    /// Existing plans feed the progression summary so intensity keeps climbing.
    @discardableResult
    static func generateAndStore(
        preferences: TrainingPreferences,
        generator: PlanGenerator,
        context: ModelContext,
        existingPlans: [WorkoutPlan]
    ) async -> WorkoutPlan {
        let histories = PerformanceHistory.histories(from: existingPlans)
        let summary = ProgressionEngine.performanceSummary(from: histories)

        let result = await generator.generatePlan(
            for: preferences,
            performanceSummary: summary.isEmpty ? nil : summary
        )

        let plan = result.blueprint.makeWorkoutPlan(
            goal: preferences.goal,
            durationMinutes: preferences.durationMinutes,
            wasModelGenerated: result.usedModel
        )
        context.insert(plan)
        try? context.save()
        return plan
    }
}
