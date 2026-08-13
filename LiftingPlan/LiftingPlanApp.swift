import SwiftUI
import SwiftData

@main
struct LiftingPlanApp: App {
    /// One shared generator (holds on-device model availability) and one shared
    /// rest timer for the whole app.
    @State private var planGenerator = PlanGenerator()
    @State private var restTimer = RestTimerModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(planGenerator)
                .environment(restTimer)
                .task { restTimer.requestNotificationAuthorization() }
        }
        .modelContainer(for: [
            TrainingPreferences.self,
            WorkoutPlan.self,
            WorkoutSession.self,
            PlannedExercise.self,
            SetLog.self,
        ])
    }
}
