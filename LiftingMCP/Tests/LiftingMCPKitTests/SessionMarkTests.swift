import Foundation
import Testing
import LiftingKit
@testable import LiftingMCPKit

/// The mark a session carries, as the tool surface offers and accepts it.
///
/// The app owns the set of marks and Claude picks from it, so this is the only
/// place he can learn what the set *is*. What the schema advertises and what the
/// call accepts have to be the same list, and a name outside it has to fail here
/// rather than at import: a plan refused on the phone for a value he could have
/// corrected in the call is a whole plan lost to a typo.
@Suite("write_plan and a session's mark")
struct SessionMarkTests {

    private func plan(_ arguments: JSONValue) throws -> (ToolOutcome, InMemoryDocuments) {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot())
        let outcome = try makeRunner(documents: documents)
            .call(ToolCatalog.writePlan, arguments: arguments)
        return (outcome, documents)
    }

    private func day(icon: String?) -> JSONValue {
        var day: [String: JSONValue] = [
            "weekday": "monday", "focus": "Push",
            "exercises": [[
                "exerciseID": "barbell-bench-press",
                "displayName": "Barbell Bench Press",
                "sets": 3, "repRange": "5",
            ]],
        ]
        if let icon { day["icon"] = .string(icon) }
        return .object(day)
    }

    private func arguments(icon: String?) -> JSONValue {
        ["title": "Block", "goal": "Get stronger", "blocks": [["days": [day(icon: icon)]]]]
    }

    // MARK: - What the schema offers

    @Test("The day schema offers exactly the marks the app can draw")
    func schemaOffersEveryMark() throws {
        let definition = ToolCatalog.writePlanDefinition
        let weeks = try #require(definition.inputSchema["properties"]?["blocks"])
        let week = try #require(weeks["items"])
        let days = try #require(week["properties"]?["days"])
        let day = try #require(days["items"])
        let icon = try #require(day["properties"]?["icon"])
        let offered = try #require(icon["enum"]?.arrayValue).compactMap(\.stringValue)

        // Built from `SessionIcon.all` rather than retyped, so a mark added to
        // the app is offered in the same commit and one removed stops being
        // offered. Asserting the list keeps that true.
        #expect(offered == SessionIcon.all.map(\.rawValue))
        #expect(offered.contains("strength"))
        #expect(offered.contains("conditioning"))
    }

    // MARK: - What the call accepts

    @Test("A chosen mark reaches the written plan")
    func chosenMarkIsWritten() throws {
        let (outcome, documents) = try plan(arguments(icon: "intervals"))

        guard case .report = outcome else {
            Issue.record("a plan with a known mark is written: \(outcome)")
            return
        }
        let written = try #require(documents.lastWrittenPlan)
        #expect(written.blocks.first?.days.first?.icon == .intervals)
    }

    @Test("A session he marked nothing carries nothing")
    func absentMarkStaysAbsent() throws {
        let (outcome, documents) = try plan(arguments(icon: nil))

        guard case .report = outcome else {
            Issue.record("a plan with no mark is written: \(outcome)")
            return
        }
        #expect(try #require(documents.lastWrittenPlan).blocks.first?.days.first?.icon == nil)
    }

    // MARK: - What it refuses, and when

    @Test("A mark the app cannot draw fails the call, names itself, and writes nothing")
    func unknownMarkIsRefusedHere() throws {
        let (outcome, documents) = try plan(arguments(icon: "deadlift"))

        guard case .failure(let message) = outcome else {
            Issue.record("an unknown mark fails the call: \(outcome)")
            return
        }
        #expect(message.contains("deadlift"))
        // The list is in the message, so the correction is in the same breath as
        // the refusal rather than a second call away.
        #expect(message.contains("strength"))
        #expect(message.contains("Nothing was written"))
        #expect(documents.lastWrittenPlan == nil)
    }

    @Test("The mark is refused for the same reason an unknown exercise is: early")
    func refusalHappensBeforeThePhoneSeesIt() throws {
        // `PlanImporter` refuses it too, and must: a plan can reach the phone
        // from somewhere other than this tool. But a plan refused at import for
        // a typo is a whole plan lost, so the tool answers first.
        let (outcome, _) = try plan(arguments(icon: "STRENGTH"))

        // And the name is read the way it is written: casing is not a typo.
        guard case .report = outcome else {
            Issue.record("a mark differing only in case is the mark: \(outcome)")
            return
        }
    }
}
