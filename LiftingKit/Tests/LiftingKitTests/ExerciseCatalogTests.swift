import Testing
import Foundation
@testable import LiftingKit

@Suite("Exercise catalog")
struct ExerciseCatalogTests {

    private func make(
        _ id: String, _ name: String,
        equipment: EquipmentType = .barbell,
        pattern: MovementPattern = .horizontalPress,
        muscles: [MuscleGroup] = [.chest],
        category: ExerciseCategory = .strength,
        aliases: [String] = []
    ) -> Exercise {
        Exercise(
            id: ExerciseID(rawValue: id), displayName: name, aliases: aliases,
            primaryMuscles: muscles, secondaryMuscles: [], equipment: equipment,
            pattern: pattern, force: nil, mechanic: .compound,
            category: category, instructions: [], mediaAsset: nil
        )
    }

    private var catalog: ExerciseCatalog {
        ExerciseCatalog(exercises: [
            make("barbell-bench-press", "Barbell Bench Press", aliases: ["flat bench"]),
            make("dumbbell-bench-press", "Dumbbell Bench Press", equipment: .dumbbell),
            make("push-up", "Push Up", equipment: .bodyweight),
            make("barbell-squat", "Barbell Squat", pattern: .squat, muscles: [.quadriceps]),
            make("assault-bike", "Assault Bike", equipment: .cardioMachine,
                 pattern: .cardio, muscles: [.quadriceps], category: .cardio),
        ])
    }

    @Test("Lookup by id returns the entry")
    func lookup() {
        #expect(catalog.exercise(id: ExerciseID(rawValue: "push-up"))?.displayName == "Push Up")
    }

    @Test("Lookup of an unknown id returns nil rather than trapping")
    func lookupMissing() {
        #expect(catalog.exercise(id: ExerciseID(rawValue: "nope")) == nil)
    }

    @Test("Search matches display names case-insensitively")
    func searchByName() {
        let results = catalog.search("bench", limit: 10)
        #expect(results.count == 2)
    }

    @Test("Search matches aliases")
    func searchByAlias() {
        let results = catalog.search("flat bench", limit: 10)
        #expect(results.first?.id == ExerciseID(rawValue: "barbell-bench-press"))
    }

    @Test("Search honors its limit")
    func searchLimit() {
        #expect(catalog.search("bench", limit: 1).count == 1)
    }

    @Test("Filtering by available equipment excludes what the user lacks")
    func filterByEquipment() {
        let filter = ExerciseFilter(equipment: [.bodyweight, .dumbbell])
        let results = catalog.exercises(matching: filter)
        #expect(results.count == 2)
        #expect(!results.contains { $0.equipment == .barbell })
    }

    @Test("Filtering by category keeps cardio out of resistance slots")
    func filterByCategory() {
        let filter = ExerciseFilter(categories: ExerciseCategory.resistance)
        #expect(!catalog.exercises(matching: filter).contains { $0.category == .cardio })
    }

    @Test("Substitutes share the pattern but are never the original")
    func substitutes() {
        let subs = catalog.substitutes(for: ExerciseID(rawValue: "barbell-bench-press"), limit: 5)
        #expect(subs.count == 2)
        #expect(!subs.contains { $0.id == ExerciseID(rawValue: "barbell-bench-press") })
        #expect(subs.allSatisfy { $0.pattern == .horizontalPress })
    }

    @Test("Substitutes for an unknown id are empty rather than a crash")
    func substitutesUnknown() {
        #expect(catalog.substitutes(for: ExerciseID(rawValue: "nope"), limit: 5).isEmpty)
    }

    @Test("The bundled catalog loads and contains every MoveKit slug")
    func bundledLoads() throws {
        let bundled = try ExerciseCatalog.bundled()
        #expect(bundled.all.count == 412)
        #expect(bundled.exercise(id: ExerciseID(rawValue: "barbell-bench-press")) != nil)
    }
}
