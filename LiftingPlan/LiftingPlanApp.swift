import SwiftUI
import SwiftData

@main
struct LiftingPlanApp: App {
    /// One shared generator (holds on-device model availability and the
    /// exercise catalog it builds plans from) and one shared rest timer for the
    /// whole app. This is the composition root: the bundled catalog is loaded
    /// once here and injected, so every plan the app stores is stamped with the
    /// version of the data that produced it.
    @State private var planGenerator: PlanGenerator
    @State private var restTimer = RestTimerModel()
    private let container: ModelContainer

    init() {
        // A store or catalog that fails to open at launch is unrecoverable —
        // there is no UI yet to show an error from, and the catalog is a bundled
        // build product, so a missing or malformed one is a build defect. Both
        // surface loudly rather than degrading silently: an in-memory container
        // would quietly stop persisting, and an empty catalog would stamp plans
        // with a version that never produced them.
        do {
            container = try StoreContainer.cloudKit()
            _planGenerator = State(initialValue: PlanGenerator(catalog: try ExerciseCatalog.bundled()))
        } catch {
            fatalError("Could not start LiftingPlan: \(error)")
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
