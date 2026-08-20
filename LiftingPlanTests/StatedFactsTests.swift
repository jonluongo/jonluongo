import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// When each fact about the lifter was last stated.
///
/// **The gap this closes.** `UserProfile` holds one value per fact and one
/// `updatedAt` for all of them, so updating the goal today restamps a constraint
/// stated eighteen months ago. The coach reads `constraints` and cannot tell a
/// shoulder that is sore now from one that was sore before the last two blocks.
/// Those are different instructions, and the record could not tell them apart.
///
/// These tests are about that distinction and nothing else. Whether a date is
/// *too old* is a training judgement and belongs to the coach; this layer
/// reports the date.
@Suite("When he said it")
struct StatedFactsTests {

    private static let march = Date(timeIntervalSince1970: 1_700_000_000)
    private static let august = Date(timeIntervalSince1970: 1_715_000_000)

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    private func catalog() throws -> ExerciseCatalog { try ExerciseCatalog.bundled() }

    private func statements(in context: ModelContext) throws -> [ProfileStatement] {
        try context.fetch(FetchDescriptor<ProfileStatement>())
    }

    // MARK: - One update, the facts it spoke to

    @Test("An update dates the facts it stated, and only those")
    func onlyTheFactsStatedAreDated() throws {
        let context = try context()
        _ = try ProfileUpdater.apply(
            ProfileUpdate(
                id: UUID(), generatedAt: Self.march,
                constraints: .stated("Left shoulder is touchy overhead")),
            to: context, catalog: try catalog())

        let recorded = try statements(in: context)
        #expect(StatedFacts.lastStated("constraints", in: recorded) == Self.march)
        #expect(StatedFacts.lastStated("goal", in: recorded) == nil, "he said nothing about it")
    }

    @Test("Taking a fact back is a statement too, made on a date")
    func withdrawingAFactIsStated() throws {
        // "He no longer avoids overhead pressing" is something he said in March
        // exactly as stating a value is. Only silence is silence.
        let context = try context()
        _ = try ProfileUpdater.apply(
            ProfileUpdate(id: UUID(), generatedAt: Self.march, avoidedPatterns: .unstated),
            to: context, catalog: try catalog())

        #expect(
            StatedFacts.lastStated("avoidedPatterns", in: try statements(in: context))
                == Self.march)
    }

    @Test("An update that states nothing this records leaves no statement behind")
    func aWeighInAloneIsNotAStatement() throws {
        // Bodyweight is a dated series where it is stored. A row saying
        // something was said on Tuesday, about nothing this holds, is a row
        // nobody can read.
        let context = try context()
        _ = try ProfileUpdater.apply(
            ProfileUpdate(
                id: UUID(), generatedAt: Self.march,
                bodyweight: [
                    BodyweightReading(date: Self.march, mass: Mass(value: 182, unit: .pounds))
                ]),
            to: context, catalog: try catalog())

        #expect(try statements(in: context).isEmpty)
    }

    // MARK: - The distinction the profile could not make

    @Test("A fact stated long ago keeps its own date when another is updated today")
    func updatingOneFactDoesNotRestampAnother() throws {
        // This is the whole point. Under `UserProfile.updatedAt` both of these
        // read as August, and the shoulder looks like current news.
        let context = try context()
        _ = try ProfileUpdater.apply(
            ProfileUpdate(
                id: UUID(), generatedAt: Self.march,
                constraints: .stated("Left shoulder is touchy overhead")),
            to: context, catalog: try catalog())
        _ = try ProfileUpdater.apply(
            ProfileUpdate(
                id: UUID(), generatedAt: Self.august, goal: .stated("Add 20 lb to the bench")),
            to: context, catalog: try catalog())

        let recorded = try statements(in: context)
        #expect(StatedFacts.lastStated("constraints", in: recorded) == Self.march)
        #expect(StatedFacts.lastStated("goal", in: recorded) == Self.august)
    }

    @Test("Saying the same thing again moves its date and nothing else's")
    func restatingMovesOnlyItsOwnDate() throws {
        let context = try context()
        _ = try ProfileUpdater.apply(
            ProfileUpdate(
                id: UUID(), generatedAt: Self.march, goal: .stated("Bench 225"),
                constraints: .stated("Shoulder")),
            to: context, catalog: try catalog())
        _ = try ProfileUpdater.apply(
            ProfileUpdate(id: UUID(), generatedAt: Self.august, goal: .stated("Bench 245")),
            to: context, catalog: try catalog())

        let recorded = try statements(in: context)
        #expect(StatedFacts.lastStated("goal", in: recorded) == Self.august)
        #expect(StatedFacts.lastStated("constraints", in: recorded) == Self.march)
    }

    @Test("Every dated fact is reported at once, each at its own date")
    func allDatesAreReportedTogether() throws {
        let context = try context()
        _ = try ProfileUpdater.apply(
            ProfileUpdate(
                id: UUID(), generatedAt: Self.march, experience: .stated(.intermediate),
                constraints: .stated("Shoulder")),
            to: context, catalog: try catalog())
        _ = try ProfileUpdater.apply(
            ProfileUpdate(id: UUID(), generatedAt: Self.august, goal: .stated("Bench 245")),
            to: context, catalog: try catalog())

        let dates = StatedFacts.dates(in: try statements(in: context))
        #expect(dates["experience"] == Self.march)
        #expect(dates["constraints"] == Self.march)
        #expect(dates["goal"] == Self.august)
        #expect(dates["equipment"] == nil)
    }

    // MARK: - The date is the coach's, not the phone's

    @Test("The date reported is when he said it, not when the phone took it in")
    func theCoachsDateIsTheOneReported() throws {
        // A phone that was off for a week takes in a week-old statement.
        // Reporting the day it arrived as the day he said it would be a small
        // lie in the one place this exists to be honest about.
        let context = try context()
        let arrival = Self.august
        _ = try ProfileUpdater.apply(
            ProfileUpdate(id: UUID(), generatedAt: Self.march, goal: .stated("Bench 225")),
            to: context, catalog: try catalog(), appliedAt: arrival)

        let recorded = try #require(try statements(in: context).first)
        #expect(recorded.generatedAt == Self.march)
        #expect(recorded.appliedAt == arrival)
        #expect(StatedFacts.lastStated("goal", in: [recorded]) == Self.march)
    }

    // MARK: - Reaching the coach

    @Test("The dates the phone kept are the dates the snapshot carries")
    func theSnapshotCarriesEachDate() throws {
        let context = try context()
        _ = try ProfileUpdater.apply(
            ProfileUpdate(
                id: UUID(), generatedAt: Self.march, constraints: .stated("Shoulder")),
            to: context, catalog: try catalog())
        _ = try ProfileUpdater.apply(
            ProfileUpdate(id: UUID(), generatedAt: Self.august, goal: .stated("Bench 245")),
            to: context, catalog: try catalog())

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)
        let profile = try #require(snapshot.profile)

        #expect(profile.statedAt["constraints"] == Self.march)
        #expect(profile.statedAt["goal"] == Self.august)
        #expect(profile.statedAt["equipment"] == nil, "he has said nothing about it")
    }

    @Test("A profile with no statements behind it carries no dates rather than wrong ones")
    func aProfileFromBeforeTheDatesCarriesNone() throws {
        // Every install that predates this build has a profile and no
        // statements. Dating those facts today would claim he restated all of
        // them the moment he updated the app.
        let context = try context()
        let profile = UserProfile()
        profile.goal = "Stated by an earlier build"
        context.insert(profile)
        try context.save()

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)

        #expect(try #require(snapshot.profile).statedAt.isEmpty)
    }

    @Test("The same update applied twice is one statement")
    func anUpdateIsRecordedOnce() throws {
        let context = try context()
        let update = ProfileUpdate(
            id: UUID(), generatedAt: Self.march, goal: .stated("Bench 225"))
        _ = try ProfileUpdater.apply(update, to: context, catalog: try catalog())
        _ = try ProfileUpdater.apply(update, to: context, catalog: try catalog())

        #expect(try statements(in: context).count == 1)
    }
}
