import Foundation
import Testing
import LiftingKit
@testable import LiftingMCPKit

@Suite("volume_by_muscle")
struct VolumeByMuscleTests {

    private func volume(weeks: Int? = nil) throws -> JSONValue {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot())
        let arguments: JSONValue = weeks.map { ["weeks": .integer($0)] } ?? [:]
        let outcome = try makeRunner(documents: documents)
            .call(ToolCatalog.volumeByMuscle, arguments: arguments)
        return try #require(outcome.report)
    }

    private func muscle(_ name: String, in report: JSONValue) throws -> JSONValue {
        let muscles = try #require(report["muscles"]?.arrayValue)
        return try #require(muscles.first { $0["muscle"] == .string(name) })
    }

    // In the four weeks before the fixture's "now" the lifter trained twice:
    // a pull day and a push day. Three working sets of bench at 5, 5 and 4 reps
    // is where every chest number below comes from.

    @Test("Sets and reps are totalled per muscle over the window")
    func totalsPerMuscle() throws {
        let chest = try muscle("chest", in: try volume(weeks: 4))

        #expect(chest["primarySets"] == 3)
        #expect(chest["primaryReps"] == 14)
    }

    @Test("Primary and secondary work are counted separately, with no weighting assumed")
    func primaryAndSecondaryStaySeparate() throws {
        let report = try volume(weeks: 4)
        let biceps = try muscle("biceps", in: report)
        let shoulders = try muscle("shoulders", in: report)

        // Curls are primary biceps; the row and the pulldown are secondary.
        #expect(biceps["primarySets"] == 3)
        #expect(biceps["primaryReps"] == 30)
        #expect(biceps["secondarySets"] == 6)
        #expect(biceps["secondaryReps"] == 59)
        // Nothing in the window trains shoulders as a primary muscle.
        #expect(shoulders["primarySets"] == 0)
        #expect(shoulders["secondarySets"] == 6)
    }

    @Test("Warmups and unfinished rows do not count as work")
    func onlyCompletedWorkingSetsCount() throws {
        // The push day logged a warmup and one row that was never finished; if
        // either counted, chest would read 4 or 5 sets instead of 3.
        #expect(try muscle("chest", in: try volume(weeks: 4))["primarySets"] == 3)
    }

    @Test("A wider window reaches back into the earlier block")
    func widerWindowReachesFurther() throws {
        let chest = try muscle("chest", in: try volume(weeks: 8))

        #expect(chest["primarySets"] == 6)
        #expect(chest["primaryReps"] == 29)
    }

    @Test("A narrow window excludes what falls outside it")
    func narrowWindowExcludes() throws {
        let report = try volume(weeks: 1)
        let muscles = try #require(report["muscles"]?.arrayValue)

        #expect(!muscles.contains { $0["muscle"] == "quadriceps" })
    }

    @Test("The window is stated, so a stale snapshot cannot be mistaken for a quiet month")
    func windowIsStated() throws {
        let report = try volume(weeks: 4)

        #expect(report["weeks"] == 4)
        #expect(report["windowEnd"] == JSONValue.date(referenceNow))
        #expect(report["snapshotGeneratedAt"] == JSONValue.date(daysAgo(1)))
        #expect(report["snapshotAgeDays"] == 1)
    }

    @Test("Sets whose exercise the catalog no longer has are reported, not silently lost")
    func unattributedSetsAreReported() throws {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot())
        // A catalog without the bench press stands in for an exercise that was
        // renamed out from under a logged history.
        let thin = ExerciseCatalog(
            exercises: try fixtureCatalog().all.filter { $0.id.rawValue != "barbell-bench-press" },
            version: 5)
        let outcome = try makeRunner(documents: documents, catalog: thin)
            .call(ToolCatalog.volumeByMuscle, arguments: ["blocks": 4])
        let report = try #require(outcome.report)

        #expect(report["unattributed"]?["sets"] == 3)
        #expect(report["unattributed"]?["exerciseIDs"] == ["barbell-bench-press"])
    }
}
