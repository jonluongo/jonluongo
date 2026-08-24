import Foundation
import Testing
import LiftingKit
@testable import LiftingMCPKit

/// Part of a list, and whether the report says so.
///
/// **A silently truncated list is a silently dropped key.** It reports success
/// while the reader plans against something that is not there — the coach
/// reading ten sessions cannot tell ten-of-ten from ten-of-two-hundred, and the
/// block he writes next is built on the difference.
@Suite("A list that is longer than what is shown")
struct BoundedListTests {

    private let letters = ["a", "b", "c", "d", "e"]

    private func report(_ list: BoundedList<String>) -> [String: JSONValue] {
        list.report(
            total: "count", items: "items", narrowing: "Raise 'limit'.",
            entry: { .string($0) })
    }

    @Test("A list shorter than its limit is returned whole and says nothing")
    func nothingCutMeansNothingSaid() {
        let keys = report(BoundedList(letters, limit: 10, keeping: .first))

        #expect(keys["count"] == .integer(5))
        #expect(keys["items"]?.arrayValue?.count == 5)
        #expect(keys["truncated"] == nil, "a key that is always there says nothing")
    }

    @Test("The total is the count before truncation, never the short one")
    func theTotalIsTheRealTotal() {
        // `recent_sessions` reported the truncated count as `sessionCount`, so
        // a slice and a whole list were indistinguishable. The type answers
        // this rather than the caller, which is why it cannot happen again.
        let keys = report(BoundedList(letters, limit: 2, keeping: .first))

        #expect(keys["count"] == .integer(5), "five matched")
        #expect(keys["items"]?.arrayValue?.count == 2, "two are here")
    }

    @Test("A cut list says how many there were and what to do about it")
    func aCutListSaysSo() throws {
        let keys = report(BoundedList(letters, limit: 2, keeping: .first))
        let said = try #require(keys["truncated"]?.stringValue)

        #expect(said.contains("5"))
        #expect(said.contains("2"))
        #expect(said.contains("Raise 'limit'"), "the fact, then the action")
    }

    @Test("Keeping the first end takes the head, keeping the last takes the tail")
    func bothEndsAreReachable() {
        // **The distinction the whole type exists for.** `trained(in:)` is
        // newest first and `history(of:in:)` is oldest first, so one wants its
        // head and the other its tail. Getting this wrong hands a coach a
        // lift's earliest sessions and hides the ones he is planning against.
        #expect(BoundedList(letters, limit: 2, keeping: .first).shown == ["a", "b"])
        #expect(BoundedList(letters, limit: 2, keeping: .last).shown == ["d", "e"])
    }

    @Test("A kept tail is still in the order it was given")
    func orderSurvivesTruncation() {
        // Oldest-first stays oldest-first, so progress still reads left to
        // right. Reversing would be this type deciding an order it was handed.
        #expect(BoundedList(letters, limit: 3, keeping: .last).shown == ["c", "d", "e"])
    }

    @Test("A limit below one returns one row rather than an empty list")
    func zeroIsNotAnAnswer() {
        // An empty array is indistinguishable from having nothing to report,
        // which would read as an empty catalog.
        #expect(BoundedList(letters, limit: 0, keeping: .first).shown == ["a"])
        #expect(BoundedList(letters, limit: -3, keeping: .first).shown == ["a"])
    }

    @Test("An empty list is not truncated and reports zero")
    func nothingIsNotASlice() {
        let keys = report(BoundedList([String](), limit: 5, keeping: .first))

        #expect(keys["count"] == .integer(0))
        #expect(keys["truncated"] == nil)
    }
}

/// The same rule, asserted through the tools that return lists.
@Suite("No tool returns a slice silently")
struct ToolTruncationTests {

    private func runner() throws -> ToolRunner {
        try makeRunner(documents: InMemoryDocuments(snapshot: fixtureSnapshot()))
    }

    private func report(_ outcome: ToolOutcome) throws -> JSONValue {
        guard case .report(let value) = outcome else {
            Issue.record("expected a report, got \(outcome)")
            return .null
        }
        return value
    }

    @Test("list_exercises honours limit, which it used to advertise and ignore")
    func listExercisesIsBounded() throws {
        // Asked without a filter so this asserts the bounding rather than the
        // catalog's contents — a test that needs four of something is a test
        // about the fixture.
        let all = try report(try runner().listExercises([:]))
        let matched = try #require(all["count"]?.intValue)
        try #require(matched > 1, "a catalog of one cannot demonstrate a cut")
        #expect(all["exercises"]?.arrayValue?.count == matched, "nothing cut, nothing said")
        #expect(all["truncated"] == nil)

        let cut = try report(try runner().listExercises(["limit": 1]))
        #expect(cut["exercises"]?.arrayValue?.count == 1)
        #expect(cut["count"]?.intValue == matched, "the total is what matched, not what fits")
        #expect(cut["truncated"] != nil)
    }

    @Test("The advertised default is the one the code applies")
    func theSchemaDoesNotLie() throws {
        // The description used to carry *Defaults to 50* beside code that
        // applied no default at all. It interpolates the constant now, so the
        // two cannot drift.
        let tools = ToolCatalog.definitions
        let listed = try #require(tools.first { $0.name == ToolCatalog.listExercises })
        let described = try #require(
            listed.inputSchema["properties"]?["limit"]?["description"]?.stringValue)

        #expect(described.contains("\(ToolRunner.defaultExerciseLimit)"))
    }

    @Test("exercise_history publishes the limit it now honours")
    func historyPublishesItsLimit() throws {
        // The mirror of the original defect: code honouring an argument the
        // schema never mentions is just as unusable as the reverse.
        let tools = ToolCatalog.definitions
        let history = try #require(tools.first { $0.name == ToolCatalog.exerciseHistory })

        #expect(history.inputSchema["properties"]?["limit"] != nil)
    }
}
