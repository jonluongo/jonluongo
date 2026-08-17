import Foundation
import Testing
import LiftingKit
@testable import LiftingMCPKit

@Suite("exercise_history")
struct ExerciseHistoryTests {

    private func history(_ id: String) throws -> JSONValue {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot())
        let outcome = try makeRunner(documents: documents)
            .call(ToolCatalog.exerciseHistory, arguments: ["id": .string(id)])
        return try #require(outcome.report)
    }

    @Test("Every logged set for the movement comes back, across every block")
    func reportsEverySet() throws {
        let report = try history("barbell-bench-press")

        // Four rows on the base block's day, five on the current block's push
        // day. The second week is prescribed but untrained, so it adds none.
        #expect(report["setCount"] == 9)
    }

    @Test("The sets are in the order they happened, oldest first")
    func setsAreInOrder() throws {
        let sets = try #require(try history("barbell-bench-press")["sets"]?.arrayValue)
        let dates = sets.compactMap { $0["date"]?.stringValue }

        #expect(dates == dates.sorted())
        #expect(dates.first == JSONValue.date(daysAgo(30)).stringValue)
        #expect(dates.last == JSONValue.date(daysAgo(2)).stringValue)
    }

    @Test("A set says what was lifted, in the unit it was entered in")
    func setsCarryTheirDetail() throws {
        let sets = try #require(try history("barbell-bench-press")["sets"]?.arrayValue)
        let short = try #require(sets.first { $0["reps"] == 4 })

        #expect(short["load"] == ["value": 225.0, "unit": "lb"])
        #expect(short["isCompleted"] == true)
        #expect(short["isWarmup"] == false)
    }

    /// The lifter is asked for no rating, so no report carries one — not even a
    /// null. A permanently-empty field would tell a reader he declined to answer
    /// when nothing put the question to him.
    @Test("No logged set in any report carries a rating the lifter never gave")
    func noReportCarriesARating() throws {
        let sets = try #require(try history("barbell-bench-press")["sets"]?.arrayValue)

        #expect(!sets.isEmpty)
        #expect(sets.allSatisfy { $0.objectValue?["rpe"] == nil })
    }

    @Test("Warmups and unfinished rows are reported and flagged, not quietly dropped")
    func warmupsAndUnfinishedRowsAreFlagged() throws {
        let sets = try #require(try history("barbell-bench-press")["sets"]?.arrayValue)

        #expect(sets.filter { $0["isWarmup"] == true }.count == 2)
        #expect(sets.filter { $0["isCompleted"] == false }.count == 1)
    }

    @Test("A set carries what was prescribed alongside it, so the two can be compared")
    func setsCarryTheirPrescription() throws {
        let sets = try #require(try history("barbell-bench-press")["sets"]?.arrayValue)
        let last = try #require(sets.last)

        #expect(last["plan"]?.stringValue == "Autumn strength")
        #expect(last["week"] == 1)
        #expect(last["focus"]?.stringValue == "Push")
        #expect(last["prescribed"]?["repRange"]?.stringValue == "5")
        #expect(last["prescribed"]?["restSeconds"] == 180)
        #expect(last["prescribed"]?["suggestedLoad"] == ["value": 225.0, "unit": "lb"])
    }

    @Test("The stated starting strength is reported alongside the history")
    func baselineIsReported() throws {
        let baselines = try #require(try history("barbell-bench-press")["baselines"]?.arrayValue)

        #expect(baselines.count == 1)
        #expect(baselines.first?["reps"] == 5)
        #expect(baselines.first?["load"] == ["value": 205.0, "unit": "lb"])
    }

    @Test("A real movement never trained reports no sets rather than failing")
    func untrainedMovementReportsEmpty() throws {
        let report = try history("push-up")

        #expect(report["setCount"] == 0)
        #expect(report["inCatalog"] == true)
    }

    @Test("An ID the catalog does not have says so, so a typo is visible immediately")
    func unknownIDIsNamed() throws {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot())
        let outcome = try makeRunner(documents: documents)
            .call(ToolCatalog.exerciseHistory, arguments: ["id": "bench-pres"])

        #expect(try #require(outcome.failureMessage).contains("bench-pres"))
    }

    @Test("Asking without an ID says which argument is missing")
    func missingArgumentIsNamed() throws {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot())
        let outcome = try makeRunner(documents: documents)
            .call(ToolCatalog.exerciseHistory, arguments: [:])

        #expect(try #require(outcome.failureMessage).contains("id"))
    }
}

@Suite("recent_sessions")
struct RecentSessionsTests {

    private func sessions(_ arguments: JSONValue = [:]) throws -> [JSONValue] {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot())
        let outcome = try makeRunner(documents: documents)
            .call(ToolCatalog.recentSessions, arguments: arguments)
        let report = try #require(outcome.report)
        return try #require(report["sessions"]?.arrayValue)
    }

    @Test("The most recent session comes first")
    func newestFirst() throws {
        let reported = try sessions()

        #expect(reported.first?["focus"]?.stringValue == "Push")
        #expect(reported.first?["date"] == JSONValue.date(daysAgo(2)))
    }

    @Test("Only days that were actually trained are sessions")
    func untrainedDaysAreNotSessions() throws {
        // Three trained days across the two blocks; the prescribed-but-untrained
        // second week is not one of them.
        #expect(try sessions().count == 3)
    }

    @Test("The limit caps how many come back")
    func limitCaps() throws {
        #expect(try sessions(["limit": 2]).count == 2)
    }

    @Test("A session says which block and week it belonged to")
    func sessionsCarryTheirBlock() throws {
        let newest = try #require(try sessions().first)

        #expect(newest["plan"]?.stringValue == "Autumn strength")
        #expect(newest["week"] == 1)
        #expect(newest["weekday"]?.stringValue == "Monday")
    }

    @Test("A session reports what was prescribed and what was logged against it")
    func sessionsCarryTheirWork() throws {
        let newest = try #require(try sessions().first)
        let exercises = try #require(newest["exercises"]?.arrayValue)
        let bench = try #require(exercises.first { $0["exerciseID"] == "barbell-bench-press" })

        #expect(bench["prescribed"]?["sets"] == 3)
        #expect(bench["prescribed"]?["repRange"]?.stringValue == "5")
        #expect(bench["completedWorkingSets"] == 3)
        #expect(try #require(bench["sets"]?.arrayValue).count == 5)
    }
}
