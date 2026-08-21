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
