import SwiftUI
import SwiftData
import LiftingKit

@main
struct LiftingPlanApp: App {
    /// One shared exercise catalog and one shared rest timer for the whole app.
    ///
    /// This is the composition root: the bundled catalog is loaded once here
    /// and injected, so everything that needs to answer a question about an
    /// exercise reads the same data, stamped with the same version.
    private let catalog: ExerciseCatalog
    @State private var restTimer = RestTimerModel()
    private let container: ModelContainer

    init() {
        // A store or catalog that fails to open at launch is unrecoverable —
        // there is no UI yet to show an error from, and the catalog is a bundled
        // build product, so a missing or malformed one is a build defect. Both
        // surface loudly rather than degrading silently: an in-memory container
        // would quietly stop persisting, and an empty catalog would leave the
        // app unable to name a single exercise.
        do {
            container = try StoreContainer.cloudKit()
            catalog = try ExerciseCatalog.bundled()
        } catch {
            fatalError("Could not start LiftingPlan: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.exerciseCatalog, catalog)
                .environment(restTimer)
                .task { restTimer.requestNotificationAuthorization() }
        }
        .modelContainer(container)
    }
}

extension EnvironmentValues {
    /// The bundled exercise catalog, loaded once at launch.
    ///
    /// Read it to answer questions about a movement — what it is called, what
    /// it trains, what could stand in for it. The default is an empty catalog
    /// so previews and tests need not supply one; the real app always injects
    /// the bundled data from `LiftingPlanApp.init`.
    @Entry var exerciseCatalog: any ExerciseCatalogProviding = ExerciseCatalog(exercises: [], version: 0)
}
