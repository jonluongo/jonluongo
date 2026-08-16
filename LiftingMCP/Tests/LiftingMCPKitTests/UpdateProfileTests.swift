import Foundation
import Testing
import LiftingKit

@testable import LiftingMCPKit

/// The tool that records what Claude has learned about the lifter.
///
/// The app asks him nothing, so this is the only way a standing fact is written
/// down. What the assertions guard is the merge: a field left out must not be
/// touched, and a field sent as `null` must return to not-known rather than to
/// some default.
@Suite("update_profile")
struct UpdateProfileTests {

    private func update(_ arguments: JSONValue) throws -> (ToolOutcome, InMemoryDocuments) {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot())
        let outcome = try makeRunner(documents: documents)
            .call(ToolCatalog.updateProfile, arguments: arguments)
        return (outcome, documents)
    }

    // MARK: - What was said is what was written

    @Test("The update lands in the folder and comes back as it was written")
    func writesAndReturnsTheUpdate() throws {
        let (outcome, documents) = try update([
            "equipmentAccess": "Full gym", "experience": "Advanced",
            "goal": "Add 20 lb to the bench", "constraints": "Left shoulder hurts overhead",
            "preferredWeekdays": ["monday", "thursday"], "preferredDurationMinutes": 60,
            "displayUnit": "kg",
        ])
        let report = try #require(outcome.report)
        let written = try #require(documents.lastWrittenProfileUpdate)

        #expect(written.equipmentAccess == .stated(.fullGym))
        #expect(written.experience == .stated(.advanced))
        #expect(written.goal == .stated("Add 20 lb to the bench"))
        #expect(written.constraints == .stated("Left shoulder hurts overhead"))
        #expect(written.preferredWeekdays == .stated([.monday, .thursday]))
        #expect(written.preferredDurationMinutes == .stated(60))
        #expect(written.displayUnit == .stated(.kilograms))
        #expect(report["writtenTo"]?.stringValue == documents.profileUpdateLocation)
        #expect(report["recorded"]?["experience"]?["value"]?.stringValue == "Advanced")
    }

    @Test("Free text is recorded in his words, not tidied")
    func textIsRecordedVerbatim() throws {
        let (_, documents) = try update(["constraints": "left shoulder — no OHP, ever"])

        #expect(
            documents.lastWrittenProfileUpdate?.constraints
                == .stated("left shoulder — no OHP, ever"))
    }

    // MARK: - Merging

    @Test("A field the call does not name is left alone rather than cleared")
    func omittedFieldsAreUntouched() throws {
        // This is what lets Claude record one thing it just learned without
        // restating, and possibly clobbering, everything else.
        let (_, documents) = try update(["equipmentAccess": "Full gym"])
        let written = try #require(documents.lastWrittenProfileUpdate)

        #expect(written.experience == .unchanged)
        #expect(written.goal == .unchanged)
        #expect(written.preferredWeekdays == .unchanged)
    }

    @Test("A field sent as null returns the fact to not-known, not to a default")
    func nullTakesTheFactBack() throws {
        let (outcome, documents) = try update(["equipmentAccess": .null])
        let written = try #require(documents.lastWrittenProfileUpdate)

        #expect(written.equipmentAccess == .unstated)
        #expect(written.experience == .unchanged)
        #expect(
            outcome.report?["recorded"]?["equipmentAccess"]?["state"]?.stringValue
                == "returned to not known")
    }

    @Test("The report says which of the three things happened to every field")
    func reportDistinguishesTheThreeStates() throws {
        let report = try #require(
            try update(["goal": "Bigger bench", "constraints": .null]).0.report)
        let recorded = try #require(report["recorded"])

        #expect(recorded["goal"]?["state"]?.stringValue == "recorded")
        #expect(recorded["constraints"]?["state"]?.stringValue == "returned to not known")
        #expect(recorded["experience"]?["state"]?.stringValue == "left as it was")
    }

    @Test("A call that names no fact is refused rather than writing a no-op")
    func emptyCallIsRefused() throws {
        let (outcome, documents) = try update([:])

        #expect(documents.lastWrittenProfileUpdate == nil)
        #expect(try #require(outcome.failureMessage).contains("without naming a single fact"))
    }

    // MARK: - Written however he said it

    @Test("An access tier written loosely is understood rather than refused")
    func equipmentIsReadLoosely() throws {
        #expect(
            try update(["equipmentAccess": "full gym"]).1
                .lastWrittenProfileUpdate?.equipmentAccess == .stated(.fullGym))
        #expect(
            try update(["equipmentAccess": "dumbbells_only"]).1
                .lastWrittenProfileUpdate?.equipmentAccess == .stated(.dumbbellsOnly))
    }

    @Test("A weekday is understood as a name or as Calendar's numbering, as write_plan does")
    func weekdaysAreReadEitherWay() throws {
        #expect(
            try update(["preferredWeekdays": ["Tue", 6]]).1
                .lastWrittenProfileUpdate?.preferredWeekdays == .stated([.tuesday, .friday]))
    }

    @Test("A single value stands in for a one-element list")
    func bareValueIsAList() throws {
        #expect(
            try update(["preferredWeekdays": "monday"]).1
                .lastWrittenProfileUpdate?.preferredWeekdays == .stated([.monday]))
    }

    @Test("A display unit written as a word is understood")
    func unitIsReadLoosely() throws {
        #expect(
            try update(["displayUnit": "pounds"]).1
                .lastWrittenProfileUpdate?.displayUnit == .stated(.pounds))
    }

    // MARK: - What is refused

    @Test("An invented access tier is refused, naming the tiers that exist")
    func unknownEquipmentIsRefused() throws {
        let (outcome, documents) = try update(["equipmentAccess": "commercial gym"])

        #expect(documents.lastWrittenProfileUpdate == nil)
        #expect(try #require(outcome.failureMessage).contains("Full gym"))
    }

    @Test("An avoided exercise the catalog does not have is refused, naming the ID")
    func unknownAvoidedExerciseIsRefused() throws {
        // Stored, it would read as a rule that is quietly excluding nothing.
        let (outcome, documents) = try update(["avoidedExercises": ["moon-press"]])

        #expect(documents.lastWrittenProfileUpdate == nil)
        let message = try #require(outcome.failureMessage)
        #expect(message.contains("moon-press"))
        #expect(message.contains(ToolCatalog.listExercises))
    }

    @Test("An avoided pattern the catalog does not use is refused, naming the ones it does")
    func unknownAvoidedPatternIsRefused() throws {
        let (outcome, documents) = try update(["avoidedPatterns": ["anti-rotation"]])

        #expect(documents.lastWrittenProfileUpdate == nil)
        #expect(try #require(outcome.failureMessage).contains("horizontal press"))
    }

    @Test("A real avoided exercise and pattern are recorded")
    func realAvoidancesAreRecorded() throws {
        let (_, documents) = try update([
            "avoidedExercises": ["barbell-deadlift"], "avoidedPatterns": ["hinge"],
        ])
        let written = try #require(documents.lastWrittenProfileUpdate)

        #expect(written.avoidedExercises == .stated([ExerciseID(rawValue: "barbell-deadlift")]))
        #expect(written.avoidedPatterns == .stated([.hinge]))
    }

    @Test("A session length that is not a number is refused rather than rounded into one")
    func badDurationIsRefused() throws {
        let (outcome, documents) = try update(["preferredDurationMinutes": "about an hour"])

        #expect(documents.lastWrittenProfileUpdate == nil)
        #expect(try #require(outcome.failureMessage).contains("whole number"))
    }

    @Test("A fact this format cannot hold is refused with the key named, not dropped")
    func unknownFieldIsNamedRatherThanDropped() throws {
        // Silently dropped, this reads as "Recorded" while the lifter's weight
        // is never written down anywhere.
        let (outcome, documents) = try update([
            "goal": "Bigger bench", "bodyweight": ["value": 180.0, "unit": "lb"],
        ])
        let message = try #require(outcome.failureMessage)

        #expect(message.contains("bodyweight"))
        #expect(documents.lastWrittenProfileUpdate == nil, "a refused update must write nothing")
    }

    @Test("An unknown key is refused even when every other field is good")
    func unknownFieldRefusesTheWholeUpdate() throws {
        let (outcome, documents) = try update([
            "experience": "Advanced", "goal": "Bigger bench", "trainingAge": 12,
        ])

        #expect(try #require(outcome.failureMessage).contains("trainingAge"))
        #expect(documents.lastWrittenProfileUpdate == nil)
    }

    @Test("A folder that cannot be written to is reported rather than passing for success")
    func brokenFolderIsReported() throws {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot())
        documents.breakTransport()

        let outcome = try makeRunner(documents: documents)
            .call(ToolCatalog.updateProfile, arguments: ["goal": "Bigger bench"])

        #expect(try #require(outcome.failureMessage).contains(documents.profileUpdateLocation))
        #expect(documents.lastWrittenProfileUpdate == nil)
    }

    @Test("Recording a fact needs no snapshot — a lifter with no history still has an identity")
    func noSnapshotIsNeeded() throws {
        let documents = InMemoryDocuments()

        let outcome = try makeRunner(documents: documents)
            .call(ToolCatalog.updateProfile, arguments: ["goal": "Bigger bench"])

        #expect(outcome.report != nil)
        #expect(documents.lastWrittenProfileUpdate?.goal == .stated("Bigger bench"))
    }

    @Test("Two updates in a row are two documents, so neither is mistaken for the other")
    func eachUpdateHasItsOwnIdentity() throws {
        let first = try #require(try update(["goal": "Bigger bench"]).1.lastWrittenProfileUpdate)
        let second = try #require(try update(["goal": "Bigger squat"]).1.lastWrittenProfileUpdate)

        #expect(first.id != second.id)
    }

    // MARK: - Nothing is lost between two calls

    /// Two calls against one folder, which is what a conversation looks like:
    /// the lifter is at the desk and his phone has not opened in between.
    private func twoUpdates(
        _ first: JSONValue, _ second: JSONValue, snapshot: TrainingSnapshot? = nil
    ) throws -> InMemoryDocuments {
        let documents = InMemoryDocuments(snapshot: snapshot ?? fixtureSnapshot())
        let runner = try makeRunner(documents: documents)
        _ = runner.call(ToolCatalog.updateProfile, arguments: first)
        _ = runner.call(ToolCatalog.updateProfile, arguments: second)
        return documents
    }

    @Test("A second update does not discard what the first recorded before the phone saw it")
    func secondUpdateFoldsInTheWaitingOne() throws {
        // The folder holds one update at a time, so overwriting would silently
        // drop the first call's facts while reporting them as written.
        let documents = try twoUpdates(
            ["goal": "Bigger bench", "constraints": "Left shoulder"],
            ["equipmentAccess": "Full gym"])
        let written = try #require(documents.lastWrittenProfileUpdate)

        #expect(written.equipmentAccess == .stated(.fullGym))
        #expect(written.goal == .stated("Bigger bench"))
        #expect(written.constraints == .stated("Left shoulder"))
    }

    @Test("The later of two updates wins where they disagree")
    func laterUpdateWinsOnTheSameFact() throws {
        let documents = try twoUpdates(["goal": "Bigger bench"], ["goal": "Bigger squat"])

        #expect(documents.lastWrittenProfileUpdate?.goal == .stated("Bigger squat"))
    }

    @Test("Taking a fact back survives being folded into a later update")
    func clearingSurvivesFolding() throws {
        let documents = try twoUpdates(["experience": .null], ["goal": "Bigger bench"])

        #expect(documents.lastWrittenProfileUpdate?.experience == .unstated)
    }

    @Test("An update the phone has already applied is not folded in again")
    func appliedUpdateIsNotReimposed() throws {
        // Re-stating a fact the phone already has would re-impose it over
        // anything changed since — the display unit is the one the lifter can
        // still change for himself.
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot())
        let runner = try makeRunner(documents: documents)
        _ = runner.call(ToolCatalog.updateProfile, arguments: ["displayUnit": "kg"])
        let applied = try #require(documents.lastWrittenProfileUpdate)

        // The phone reports having taken that one in.
        let after = InMemoryDocuments(
            snapshot: fixtureSnapshot(
                profile: fixtureProfile(appliedProfileUpdateID: applied.id)))
        try after.writeProfileUpdate(applied)
        _ = try makeRunner(documents: after)
            .call(ToolCatalog.updateProfile, arguments: ["goal": "Bigger bench"])

        #expect(after.lastWrittenProfileUpdate?.displayUnit == .unchanged)
        #expect(after.lastWrittenProfileUpdate?.goal == .stated("Bigger bench"))
    }

    @Test("An unreadable waiting update is reported rather than quietly replaced")
    func unreadableWaitingUpdateIsReported() throws {
        // Replacing it would discard whatever it recorded, which is exactly the
        // loss this whole path exists to prevent.
        let documents = BrokenReadDocuments()

        let outcome = try makeRunner(documents: documents)
            .call(ToolCatalog.updateProfile, arguments: ["goal": "Bigger bench"])

        #expect(try #require(outcome.failureMessage).contains("cannot be read"))
        #expect(documents.lastWrittenProfileUpdate == nil)
    }
}

/// A folder whose waiting profile update cannot be read, and nothing else.
private final class BrokenReadDocuments: TrainingDocuments, @unchecked Sendable {
    struct Broken: Error, LocalizedError {
        var errorDescription: String? { "the file is half-synced" }
    }

    private let lock = NSLock()
    private var written: ProfileUpdate?

    var lastWrittenProfileUpdate: ProfileUpdate? { lock.withLock { written } }

    var snapshotLocation: String { "/fixture/Documents/snapshot.json" }
    var planLocation: String { "/fixture/Documents/plan.json" }
    var profileUpdateLocation: String { "/fixture/Documents/profile-update.json" }

    func readSnapshot() throws -> TrainingSnapshot? { fixtureSnapshot() }
    func writePlan(_ plan: PlanDocument) throws {}
    func readProfileUpdate() throws -> ProfileUpdate? { throw Broken() }
    func writeProfileUpdate(_ update: ProfileUpdate) throws {
        lock.withLock { written = update }
    }
}
