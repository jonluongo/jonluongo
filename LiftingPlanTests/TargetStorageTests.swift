import Testing
import Foundation
import SwiftData
@testable import LiftingPlan
import LiftingKit

/// Whether a typed target survives the store.
///
/// **The schema validating is not the value persisting.** `StoreContainer.cloudKit()`
/// constructs without throwing, and the app launches — which proves SwiftData and
/// CloudKit accept `Target?` as an attribute, and proves nothing at all about
/// whether a value put into one comes back out.
@Suite("A target in the store")
struct TargetStorageTests {

    private func saved(_ target: Target?) throws -> PlannedSet {
        let context = try StoreFixture.context()
        let set = PlannedSet(setIndex: 0, target: target)
        context.insert(set)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PlannedSet>())
        return try #require(fetched.first)
    }

    @Test("A rep target comes back out")
    func repsSurvive() throws {
        #expect(try saved(.repetitions(low: 5, high: 8)).target == .repetitions(low: 5, high: 8))
    }

    @Test("Every case comes back out")
    func everyCaseSurvives() throws {
        let cases: [Target] = [
            .repetitions(low: 5, high: nil),
            .repetitionsToFailure,
            .time(low: 45, high: nil),
            .distance(low: 40, high: nil, unit: .metres),
        ]
        for target in cases {
            #expect(try saved(target).target == target, "\(target)")
        }
    }

    @Test("An unstated target stays unstated")
    func absenceSurvives() throws {
        #expect(try saved(nil).target == nil)
    }
}

/// Whether the work of a performed set survives the store, and whether the
/// store can hold two measures at once.
///
/// **The same guard its mirror already had.** `PlannedSet` keeps four raw
/// columns behind one typed `target` and a round-trip test; `PerformedSet` kept
/// three peer optionals, public, with the invariant living in whichever caller
/// happened to be writing. Nothing produced a two-measure row — `WorkDone`
/// closed that — but *unwritten* and *unreachable* are different guarantees,
/// and only one of them survives the next person.
///
/// This is grade-three verification and it is load-bearing here, not
/// belt-and-braces: at this boundary the compiler lies. SwiftData accepts a
/// Codable enum with associated values as an attribute and silently stores
/// nothing, which is how the `Target` defect was found — by a test, and not by
/// launching the app.
@Suite("The work of a set in the store")
struct WorkStorageTests {

    private func saved(_ work: WorkDone?) throws -> PerformedSet {
        let context = try StoreFixture.context()
        context.insert(PerformedSet(setIndex: 0, work: work))
        try context.save()

        return try #require(try context.fetch(FetchDescriptor<PerformedSet>()).first)
    }

    @Test("Every measure comes back out as itself")
    func everyMeasureSurvives() throws {
        let cases: [WorkDone] = [
            .repetitions(8),
            .repetitions(0),
            .time(seconds: 45),
            .distance(Distance(value: 40, unit: .metres)),
            .distance(Distance(value: 40, unit: .yards)),
        ]
        for work in cases {
            #expect(try saved(work).work == work, "\(work)")
        }
    }

    @Test("A carry keeps the unit it was prescribed in")
    func unitsAreNotConverted() throws {
        // Forty metres and forty yards are different work, and a store that
        // normalised them would be deciding something nobody asked it to.
        let yards = try saved(.distance(Distance(value: 40, unit: .yards)))
        #expect(yards.work?.carried?.unit == .yards)
    }

    @Test("A set with no figure comes back with none, and keeps no measure")
    func aBlankSetKeepsNothing() throws {
        // Documented rather than lossy: *which* measure a blank set was
        // performed in is a fact the prescription already states, so keeping it
        // here would be the same fact in two places. The row's existence is
        // what says the set happened.
        #expect(try saved(nil).work == nil)
        #expect(try saved(.repetitions(nil)).work == nil)
        #expect(try saved(.time(seconds: nil)).work == nil)
    }

    @Test("Writing a second measure clears the first, so a row never states two")
    func aRowNeverStatesTwo() throws {
        // The invariant the three public optionals could not hold. A set logged
        // as forty-five seconds and then corrected to eight reps is eight reps,
        // not both — and there is no way through this type to make it both.
        let context = try StoreFixture.context()
        let set = PerformedSet(setIndex: 0, work: .time(seconds: 45))
        context.insert(set)
        set.work = .repetitions(8)
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<PerformedSet>()).first)
        #expect(fetched.work == .repetitions(8))
    }
}

