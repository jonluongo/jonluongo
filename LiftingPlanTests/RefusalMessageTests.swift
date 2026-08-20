import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// A watcher a test drives by hand, so an arrival happens when it says so.
@MainActor
private final class ManualWatcher: DocumentArrivalWatching {
    private var onArrival: (@MainActor () async -> Void)?

    func start(onArrival: @escaping @MainActor () async -> Void) {
        self.onArrival = onArrival
    }

    func stop() {}

    func announceArrival() async {
        await onArrival?()
    }
}

/// What the lifter reads when a document is turned away.
///
/// A refusal is written to whoever wrote the document. Put verbatim into an
/// alert on a phone — *"Send it under a key the format has"*, *"Send one entry
/// in 'weeks' for every week of the block"* — it addresses somebody who is not
/// there and tells the person who is nothing he can do. These tests hold both
/// halves: the lifter is told what happened and what to do, and the author's
/// own sentence survives underneath so that relaying it is possible.
@MainActor
@Suite("What a refusal says to the lifter")
struct RefusalMessageTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    private func folder() throws -> DocumentFolder {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return DocumentFolder(directory: url)
    }

    /// Puts `json` in the folder as the waiting plan and reads it in.
    private func messageAfterReading(_ json: String) async throws -> String {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try Data(json.utf8).write(to: folder.url.appending(path: DocumentFolder.planFilename))
        let watcher = ManualWatcher()
        let inbox = DocumentInbox(
            transport: folder, watcher: watcher, context: try context(),
            catalog: try ExerciseCatalog.bundled())

        inbox.start()
        await watcher.announceArrival()
        return try #require(inbox.errorMessage)
    }

    /// The document the owner has sitting in his folder right now: a plan an
    /// earlier build wrote, stating a length beside a single week of days.
    private static let planFromAnEarlierBuild = """
        {
          "version": 1, "id": "5C5C4C51-9E15-4F35-8D9F-0F1D2B3A4C5D",
          "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z",
          "title": "Autumn strength", "goal": "Bigger squat", "weekCount": 8,
          "days": [{
            "weekday": 2, "focus": "Lower",
            "exercises": [{
              "exerciseID": "barbell-squat", "displayName": "Barbell Squat",
              "sets": 3, "repRange": "5"
            }]
          }]
        }
        """

    // MARK: - The lifter is told something he can act on

    @Test("A refused plan tells the lifter what happened and what to do about it")
    func refusalIsAddressedToTheLifter() async throws {
        let message = try await messageAfterReading(Self.planFromAnEarlierBuild)

        #expect(message.contains("Ask your coach to send it again"))
        #expect(
            message.contains("Nothing you have already logged has changed"),
            "the first thing he will wonder is whether his log survived")
    }

    @Test("The sentence written for the plan's author is kept, so relaying it is the fix")
    func authorsSentenceSurvives() async throws {
        let message = try await messageAfterReading(Self.planFromAnEarlierBuild)

        #expect(message.contains("says it runs 8 blocks but states 1"))
        #expect(message.contains("writing it again is the whole of the fix"))
    }

    @Test("An unknown key still names the key, underneath something the lifter can use")
    func unknownKeyIsStillNamed() async throws {
        let message = try await messageAfterReading("""
            {
              "version": 3, "id": "5C5C4C51-9E15-4F35-8D9F-0F1D2B3A4C5D",
              "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z",
              "dropSets": true, "weeks": []
            }
            """)

        #expect(message.contains("'dropSets'"))
        #expect(message.contains("Ask your coach to send it again"))
    }

    @Test("An exercise the catalog does not have reads the same way")
    func unknownExerciseIsFramedToo() async throws {
        let message = try await messageAfterReading("""
            {
              "version": 3, "id": "5C5C4C51-9E15-4F35-8D9F-0F1D2B3A4C5D",
              "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z",
              "weeks": [{"days": [{"weekday": 2, "exercises": [{
                "exerciseID": "moon-press", "displayName": "Moon Press", "sets": 3
              }]}]}]
            }
            """)

        #expect(message.contains("moon-press"))
        #expect(message.contains("Ask your coach to send it again"))
    }

    @Test("A document from a later format keeps its own remedy, which he can act on himself")
    func laterVersionKeepsItsRemedy() async throws {
        let message = try await messageAfterReading("""
            {
              "version": 99, "id": "5C5C4C51-9E15-4F35-8D9F-0F1D2B3A4C5D",
              "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z", "weeks": []
            }
            """)

        #expect(message.contains("update the app"))
        #expect(message.contains("Ask your coach to send it again"))
    }

    // MARK: - Everything else is left alone

    @Test("A failure that is not about the document's contents is shown as it is")
    func nonDocumentFailuresAreNotReframed() async throws {
        let message = try await messageAfterReading("{ this is not JSON at all")

        #expect(
            !message.contains("Ask your coach to send it again"),
            "a malformed file is not a plan a coach can be shown and asked to fix")
    }
}
