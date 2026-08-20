import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import LiftingKit

/// Lets a notification be seen and heard while the app is open.
///
/// iOS delivers a notification that fires in the foreground to the delegate and
/// nowhere else; with no delegate it is filed silently. The rest timer's whole
/// job is to interrupt a lifter who is looking at the screen, so this says to
/// present it as a banner, with its sound, exactly as it would on the lock
/// screen. It decides nothing else and holds no state.
private final class ForegroundAlerts: NSObject, UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

@main
struct LiftingPlanApp: App {

    /// Held for the life of the app: `UNUserNotificationCenter.delegate` is a
    /// weak reference, and a delegate that is deallocated is a notification
    /// nobody hears.
    private static let foregroundAlerts = ForegroundAlerts()
    @Environment(\.scenePhase) private var scenePhase
    /// One shared exercise catalog and one shared rest timer for the whole app.
    ///
    /// This is the composition root: the bundled catalog is loaded once here
    /// and injected, so everything that needs to answer a question about an
    /// exercise reads the same data, stamped with the same version.
    private let catalog: ExerciseCatalog
    @State private var restTimer = RestTimerModel()
    /// What the lifter has said about his own clock — on or off, and how long
    /// on each exercise. One instance for the app, like the timer it feeds.
    @State private var restPreferences = RestPreferences()
    private let container: ModelContainer
    /// The shared iCloud folder both machines see. The snapshot goes out
    /// through it and plans and profile updates come in through it; nothing
    /// else in the app knows there is a file involved.
    private let transport: ICloudDocumentTransport
    /// Takes in a plan or a profile update the moment one lands, so no refresh
    /// is ever asked for.
    @State private var documentInbox: DocumentInbox
    /// Writes the snapshot out, and remembers when it could not.
    @State private var snapshotOutbox: SnapshotOutbox

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
        // Composed here for the same reason the catalog is: one transport, so
        // the document written out and the document read in cannot end up in
        // different folders. Nothing is resolved yet — the iCloud container is
        // looked up when a document actually moves.
        let transport = ICloudDocumentTransport()
        self.transport = transport
        _documentInbox = State(initialValue: DocumentInbox(
            transport: transport, watcher: UbiquitousDocumentWatcher(),
            context: container.mainContext, catalog: catalog
        ))
        _snapshotOutbox = State(initialValue: SnapshotOutbox(
            transport: transport, context: container.mainContext, catalog: catalog
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.exerciseCatalog, catalog)
                .environment(restTimer)
                .environment(restPreferences)
                .environment(documentInbox)
                .environment(snapshotOutbox)
                .task {
                    // Presented in the foreground too. Without a delegate iOS
                    // silently swallows a notification that fires while the app
                    // is open — which, during a workout, is every one of them.
                    //
                    // **Permission is not asked here.** It used to be, which
                    // meant the first thing a new install did was put a system
                    // dialog in front of a screen reading *No routine yet* — an
                    // app whose whole premise is that it asks him nothing,
                    // opening by asking him something he has no way to judge.
                    // `RestTimerModel` asks when the first rest starts, which
                    // is the moment the answer means anything.
                    UNUserNotificationCenter.current().delegate = Self.foregroundAlerts
                }
                // Started once, for the life of the app: anything arriving
                // from the Mac is taken in wherever the lifter happens to be.
                // The snapshot goes back out the moment something lands, so the
                // coach is never reading a record written before the plan he
                // just sent — see `DocumentInbox.onApplied`.
                .task {
                    documentInbox.onApplied = { [snapshotOutbox] in
                        await snapshotOutbox.exportSnapshot()
                    }
                    documentInbox.start()
                }
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

    /// Writes the snapshot on the way out, and asks for the time to finish.
    ///
    /// The export is a task rather than a straight call because the write
    /// resolves the iCloud container, which must not happen on the main thread;
    /// that also means the app could be suspended mid-write, so a background
    /// task assertion holds it awake until the file has landed. What went wrong
    /// is not shown here — nothing can be presented from a scene that is
    /// leaving — but `SnapshotOutbox` keeps it, and `RootView` shows it the
    /// next time the lifter opens the app.
    @MainActor
    private func exportSnapshot() {
        let assertion = BackgroundExportAssertion()
        assertion.begin()
        Task {
            await snapshotOutbox.exportSnapshot()
            assertion.end()
        }
    }
}

/// Keeps the app running long enough to finish one piece of work after it has
/// left the screen.
///
/// Call `begin()` before starting work on the way to the background and `end()`
/// when it finishes. Without it iOS may suspend the app as soon as the scene
/// transition returns, cutting the snapshot write off part-way and leaving the
/// coach reading a stale document. Ending it twice, or ending one that never
/// began, does nothing.
///
/// Depends on: `UIApplication`'s background task assertions.
@MainActor
private final class BackgroundExportAssertion {

    private var identifier = UIBackgroundTaskIdentifier.invalid

    func begin() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Snapshot export") {
            // Expiry means the system wants the time back now; releasing it is
            // the only correct answer, and the export retries on the next
            // background.
            MainActor.assumeIsolated { [weak self] in self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
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
