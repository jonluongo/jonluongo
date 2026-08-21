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

/// What the user reads when a document is turned away.
///
/// A refusal is written to whoever wrote the document. Put verbatim into an
/// alert on a phone — *"Send it under a key the format has"*, *"Send one entry
/// in 'weeks' for every week of the block"* — it addresses somebody who is not
/// there and tells the person who is nothing he can do. These tests hold both
/// halves: the user is told what happened and what to do, and the author's
/// own sentence survives underneath so that relaying it is possible.
@MainActor
@Suite("What a refusal says to the user")
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
    /// A plan written in the shape every version up to 5 used.
    ///
    /// **It is refused for its version now, not for its contents.** Version 6
    /// states a flat list of sessions and has no routine, no block label and no
    /// weekday, so there is no honest reading of this into it — the refusal says
    /// exactly that rather than picking over keys it was never going to accept.
    private static let planFromAnEarlierBuild = """
        {
          "version": 5, "id": "5C5C4C51-9E15-4F35-8D9F-0F1D2B3A4C5D",
          "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z",
          "title": "Autumn strength", "goal": "Bigger squat",
          "days": [{
            "weekday": 2, "focus": "Lower",
            "exercises": [{
              "exerciseID": "barbell-squat", "displayName": "Barbell Squat",
              "sets": 3, "repRange": "5"
            }]
          }]
        }
        """

    // MARK: - The user gets one short line

    @Test("A refusal reaches the user as one short line, not a format lesson")
    func aRefusalIsShort() async throws {
        // **The coach has already been told.** `write_plan` decodes the document
        // and hands the full refusal back at the moment he writes it, so the
        // paragraph naming the key, its location and the remedy has already
        // reached the one person who can act on it. Repeating it on the phone
        // filled an alert with instructions for somebody else.
        let message = try await messageAfterReading(Self.planFromAnEarlierBuild)

        #expect(message.count < 90, "\(message.count) characters: \(message)")
        #expect(!message.contains("Nothing was taken in"))
        #expect(!message.contains("Update the app"), "that sentence is written for the coach")
    }

    @Test("It still says which failure this is, by the number that identifies it")
    func theReasonIsNamed() async throws {
        // Short is not vague. Two refusals must not read alike, or the user
        // cannot tell his coach which one he is looking at.
        let message = try await messageAfterReading(Self.planFromAnEarlierBuild)

        #expect(message.contains("version 5"))
        #expect(message.contains("version 6"))
    }

    @Test("An unknown key is named, and nothing else is")
    func unknownKeyIsNamed() async throws {
        let message = try await messageAfterReading("""
            {
              "version": 6, "id": "5C5C4C51-9E15-4F35-8D9F-0F1D2B3A4C5D",
              "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z",
              "dropSets": true, "sessions": []
            }
            """)

        #expect(message.contains("dropSets"))
        #expect(message.count < 90, "\(message)")
    }

    @Test("An exercise the catalog does not have is named the same way")
    func unknownExerciseIsNamed() async throws {
        let message = try await messageAfterReading("""
            {
              "version": 6, "id": "5C5C4C51-9E15-4F35-8D9F-0F1D2B3A4C5D",
              "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z",
              "sessions": [{"blockOrdinal": 1, "ordinal": 1, "entries": [{
                "exerciseID": "moon-press", "displayName": "Moon Press",
                "sets": [{"target": "5"}]
              }]}]
            }
            """)

        #expect(message.contains("moon-press"))
        #expect(message.count < 90, "\(message)")
    }

    @Test("Two different refusals do not read alike")
    func refusalsAreTellableApart() async throws {
        let version = try await messageAfterReading(Self.planFromAnEarlierBuild)
        let key = try await messageAfterReading("""
            {
              "version": 6, "id": "5C5C4C51-9E15-4F35-8D9F-0F1D2B3A4C5D",
              "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z",
              "dropSets": true, "sessions": []
            }
            """)

        #expect(version != key)
    }

    // MARK: - Everything else is left alone

    @Test("A failure that is not about the document's contents is shown as it is")
    func nonDocumentFailuresAreNotReframed() async throws {
        let message = try await messageAfterReading("{ this is not JSON at all")

        #expect(
            message.contains("JSON") || message.contains("data"),
            "a malformed file is not a refusal — it is shown as whatever it was: \(message)")
    }
}
