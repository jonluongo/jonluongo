import SwiftUI
import SwiftData

@main
struct LiftingPlanApp: App {
    /// One shared generator (holds on-device model availability) and one shared
    /// rest timer for the whole app.
    @State private var planGenerator = PlanGenerator()
    @State private var restTimer = RestTimerModel()
    private let container: ModelContainer

    init() {
        // A container that fails to open is unrecoverable — there is no store to
        // show a UI-level error from, so this surfaces loudly rather than
        // silently falling back to an in-memory container that would quietly
        // stop persisting.
        do {
            container = try StoreContainer.cloudKit()
        } catch {
            fatalError("Could not open the CloudKit-backed store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(planGenerator)
                .environment(restTimer)
                .task { restTimer.requestNotificationAuthorization() }
        }
        .modelContainer(container)
    }
}
