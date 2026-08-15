import Testing
import SwiftData
import Foundation
@testable import LiftingPlan

/// A catalog fixture that reports a version no bundled catalog will ever have.
///
/// Used by `CatalogVersionStampingTests` to tell a version that was genuinely
/// carried from the injected catalog apart from one that merely happens to
/// equal the bundled catalog's. Depends on: `ExerciseCatalogProviding`.
private struct StubCatalog: ExerciseCatalogProviding {
    let version: Int
    var all: [Exercise] { [] }
    func exercise(id: ExerciseID) -> Exercise? { nil }
    func search(_ query: String, limit: Int) -> [Exercise] { [] }
    func exercises(matching filter: ExerciseFilter) -> [Exercise] { [] }
    func substitutes(for id: ExerciseID, limit: Int) -> [Exercise] { [] }
}

/// Guards the one thing `TrainingPlan.catalogVersion` exists for: that a plan
/// built by the app records the catalog generation that actually produced it.
///
/// These tests deliberately go through `PlanCoordinator.generateAndStore` —
/// the production path — rather than constructing a `TrainingPlan` with a
/// version and reading it back, which would prove only that SwiftData stores
/// integers.
@Suite("Catalog version stamping")
@MainActor
struct CatalogVersionStampingTests {

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    @Test("A plan generated through the coordinator carries the bundled catalog's version")
    func productionPathStampsBundledCatalogVersion() async throws {
        let catalog = try ExerciseCatalog.bundled()
        // The expectation below is only meaningful while the bundled version
        // differs from the model's own default — otherwise a plan that was
        // never stamped would pass by coincidence.
        #expect(
            catalog.version != TrainingPlan().catalogVersion,
            "The bundled catalog version matches TrainingPlan's default, so this test can no longer tell a stamped plan from an unstamped one."
        )

        let context = try context()
        let profile = UserProfile(goal: "Get strong")
        context.insert(profile)

        let plan = try await PlanCoordinator.generateAndStore(
            profile: profile,
            weekdays: [.monday, .thursday],
            durationMinutes: 45,
            generator: PlanGenerator(catalog: catalog),
            context: context,
            existingPlans: []
        )

        #expect(plan.catalogVersion == catalog.version)
    }

    @Test("The stamp comes from the injected catalog, not from the bundle")
    func stampFollowsTheInjectedCatalog() async throws {
        let stub = StubCatalog(version: 4242)
        let context = try context()
        let profile = UserProfile(goal: "Get strong")
        context.insert(profile)

        let plan = try await PlanCoordinator.generateAndStore(
            profile: profile,
            weekdays: [.monday],
            durationMinutes: 45,
            generator: PlanGenerator(catalog: stub),
            context: context,
            existingPlans: []
        )

        #expect(plan.catalogVersion == stub.version)
    }

    @Test("The stamp survives the save, so a synced plan carries it too")
    func stampIsPersisted() async throws {
        let stub = StubCatalog(version: 4242)
        let context = try context()
        let profile = UserProfile(goal: "Get strong")
        context.insert(profile)

        _ = try await PlanCoordinator.generateAndStore(
            profile: profile,
            weekdays: [.monday],
            durationMinutes: 45,
            generator: PlanGenerator(catalog: stub),
            context: context,
            existingPlans: []
        )

        let stored = try #require(try context.fetch(FetchDescriptor<TrainingPlan>()).first)
        #expect(stored.catalogVersion == stub.version)
    }

    @Test("The generator reports the version of the catalog it was built with")
    func generatorExposesCatalogVersion() throws {
        let bundled = try ExerciseCatalog.bundled()
        #expect(PlanGenerator(catalog: bundled).catalogVersion == bundled.version)
        #expect(PlanGenerator(catalog: StubCatalog(version: 4242)).catalogVersion == 4242)
    }
}
