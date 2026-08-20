import Foundation
import Testing
import LiftingKit
@testable import LiftingMCPKit

/// Every figure a tool reports, re-derived from the log it was read from.
///
/// **Why this exists.** Each report has its own suite proving it says the right
/// thing about a fixture. None of them asks the question a reader of two reports
/// actually has: *do these agree with each other, and with the record?* That gap
/// is not theoretical — `workingWeights` in the context resource stated a
/// carry's load with no distance beside it for as long as it did precisely
/// because nothing compared one report against another.
///
/// So this suite computes each total directly from `TrainingSnapshot.log` and
/// asserts the tools arrive at the same number. It is the automated form of a
/// probe run by hand on 2026-08-20 — plan written by the server, logged on the
/// phone, exported, read back — which agreed on every figure and would not have
/// run again without someone remembering to run it.
///
/// It deliberately re-implements the arithmetic rather than calling the server's
/// own helpers. A cross-check sharing its subject's code checks nothing.
@Suite("What the tools report against what was logged")
struct ReportedTotalsTests {

    private let snapshot = fixtureSnapshot()

    private func report(_ tool: String, _ arguments: JSONValue = [:]) throws -> JSONValue {
        let outcome = try makeRunner(documents: InMemoryDocuments(snapshot: snapshot))
            .call(tool, arguments: arguments)
        return try #require(outcome.report)
    }

    /// Completed working sets for one movement, counted from the log itself.
    private func loggedWorkingSets(_ id: String) -> [LoggedSetRecord] {
        snapshot.log.filter {
            $0.exerciseID == ExerciseID(rawValue: id) && $0.isCompleted && !$0.isWarmup
        }
    }

    /// Wide enough to reach every set the fixture holds, so the comparison is
    /// against the whole log rather than against whatever the default window
    /// happens to be. The window itself is `VolumeTests`' subject; this suite is
    /// about the arithmetic inside it.
    private let everything: JSONValue = ["weeks": 520]

    // MARK: - One movement's history

    @Test("Every set the log holds for a movement is a set its history reports")
    func historyReportsEverySetLogged() throws {
        let id = "barbell-bench-press"
        let logged = snapshot.log.filter { $0.exerciseID == ExerciseID(rawValue: id) }
        let reported = try #require(try report(ToolCatalog.exerciseHistory, ["id": .string(id)]))

        #expect(reported["setCount"] == .integer(logged.count))
        #expect(try #require(reported["sets"]?.arrayValue).count == logged.count)
    }

    @Test("The repetitions in a movement's history are the repetitions in the log")
    func historyRepsMatchTheLog() throws {
        let id = "barbell-bench-press"
        let sets = try #require(
            try report(ToolCatalog.exerciseHistory, ["id": .string(id)])["sets"]?.arrayValue)
        let reportedReps = sets.compactMap { $0["reps"]?.intValue }.reduce(0, +)
        let loggedReps = snapshot.log
            .filter { $0.exerciseID == ExerciseID(rawValue: id) }
            .map(\.reps).reduce(0, +)

        #expect(reportedReps == loggedReps)
    }

    // MARK: - Volume against the same sets

    @Test("A muscle's primary volume counts the sets the log actually holds for it")
    func volumeCountsTheLoggedSets() throws {
        // Chest is the fixture catalog's primary for the bench press and for
        // nothing else in it, so its primary total is that movement's working
        // sets and no others.
        let bench = loggedWorkingSets("barbell-bench-press")
        let muscles = try #require(
            try report(ToolCatalog.volumeByMuscle, everything)["muscles"]?.arrayValue)
        let chest = try #require(muscles.first { $0["muscle"] == "chest" })

        #expect(chest["primarySets"] == .integer(bench.count))
        #expect(chest["primaryReps"] == .integer(bench.map(\.reps).reduce(0, +)))
    }

    @Test("No muscle is credited with more sets than the log holds in total")
    func noMuscleOutrunsTheLog() throws {
        // A muscle counted twice for one set, or a warm-up counted as work,
        // shows up here without needing to know which muscle it was.
        let working = snapshot.log.filter { $0.isCompleted && !$0.isWarmup }.count
        let muscles = try #require(
            try report(ToolCatalog.volumeByMuscle, everything)["muscles"]?.arrayValue)

        for muscle in muscles {
            let primary = muscle["primarySets"]?.intValue ?? 0
            #expect(primary <= working, "\(muscle["muscle"] ?? .null) claims more than was logged")
        }
    }

    @Test("A row is in the record, in the volume, or neither — and the two reports agree")
    func historyAndVolumeSplitTheSameRowsThreeWays() throws {
        // Three kinds of row and two reports over them, which is exactly where
        // they could drift apart. A warm-up happened and belongs in the record,
        // and is not working volume. A row seeded on screen and never ticked is
        // in the record too — the app shows what was asked for — and it is not
        // work either: nobody performed it.
        let id = "barbell-bench-press"
        let all = snapshot.log.filter { $0.exerciseID == ExerciseID(rawValue: id) }
        let warmups = all.filter(\.isWarmup)
        let untouched = all.filter { !$0.isWarmup && !$0.isCompleted }
        #expect(!warmups.isEmpty, "the fixture must carry one for this to mean anything")
        #expect(!untouched.isEmpty, "and one of these")

        let history = try #require(
            try report(ToolCatalog.exerciseHistory, ["id": .string(id)])["sets"]?.arrayValue)
        #expect(history.count == all.count, "every row, warm-ups and untouched included")

        let muscles = try #require(
            try report(ToolCatalog.volumeByMuscle, everything)["muscles"]?.arrayValue)
        let chest = try #require(muscles.first { $0["muscle"] == "chest" })
        #expect(
            chest["primarySets"] == .integer(all.count - warmups.count - untouched.count),
            "neither the warm-up nor the row he never ticked is volume")
    }

    // MARK: - Sessions against the days they were logged on

    @Test("Every day the log was written on is a session the report names")
    func sessionsMatchTheDaysLoggedOn() throws {
        struct Day: Hashable {
            let routine: UUID
            let block: Int
            let weekday: Weekday
        }
        let logged = Set(
            snapshot.log.map { Day(routine: $0.routineID, block: $0.blockOrdinal, weekday: $0.weekday) })
        let sessions = try #require(
            try report(ToolCatalog.recentSessions, ["limit": 100])["sessions"]?.arrayValue)

        #expect(sessions.count == logged.count)
    }

    @Test("A session's completed working sets are the ones the log holds for that day")
    func eachSessionCountsItsOwnSets() throws {
        // Stated per exercise rather than per session, because a session's
        // total says nothing about which movement carried it.
        let sessions = try #require(
            try report(ToolCatalog.recentSessions, ["limit": 100])["sessions"]?.arrayValue)
        let reported = sessions
            .compactMap { $0["exercises"]?.arrayValue }
            .flatMap { $0 }
            .compactMap { $0["completedWorkingSets"]?.intValue }
            .reduce(0, +)
        let logged = snapshot.log.filter { $0.isCompleted && !$0.isWarmup }.count

        #expect(reported == logged)
    }
}
