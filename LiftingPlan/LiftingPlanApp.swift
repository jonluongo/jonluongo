import SwiftUI
import SwiftData
import OSLog
import LiftingKit

@main
struct LiftingPlanApp: App {
    @Environment(\.scenePhase) private var scenePhase
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
        // Exporting on background, rather than behind a button, is what keeps
        // the snapshot honest: a coach reading a stale document is confidently
        // wrong, which is worse than one reading nothing, because stale data
        // does not look like absence. Backgrounding is the moment the lifter
        // has finished with the app and the log is complete.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            exportSnapshot()
        }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LiftingPlan", category: "snapshot"
    )

    /// Writes the current state of the store where Claude can read it.
    ///
    /// The failure is logged rather than propagated because there is nowhere
    /// to propagate it to: the app is already leaving the screen, so no UI can
    /// present it. Nothing is lost — the store is the record and the next
    /// background writes the snapshot again — so this is handling the error,
    /// not discarding it.
    @MainActor
    private func exportSnapshot() {
        do {
            let snapshot = try SnapshotExporter.export(
                from: container.mainContext, catalogVersion: catalog.version
            )
            try SnapshotFileWriter().write(snapshot)
        } catch {
            Self.logger.error(
                "Snapshot export failed: \(error.localizedDescription, privacy: .public)"
            )
        }
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
