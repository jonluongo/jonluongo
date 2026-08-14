import Testing
import Foundation
@testable import LiftingPlan

@Suite("Catalog integrity")
struct CatalogIntegrityTests {

    /// Loads the bundled catalog, failing the test loudly if it cannot be read.
    /// Deliberately not `try?` — a missing or malformed catalog must surface as
    /// the real error, not as an empty result.
    private func loaded() throws -> ExerciseCatalog {
        try ExerciseCatalog.bundled()
    }

    @Test("The catalog holds exactly the 412 MoveKit exercises")
    func count() throws {
        #expect(try loaded().all.count == 412)
    }

    @Test("Every id is unique")
    func idsUnique() throws {
        let all = try loaded().all
        #expect(Set(all.map(\.id)).count == all.count)
    }

    @Test("Every entry has a display name")
    func namesPresent() throws {
        for exercise in try loaded().all {
            #expect(!exercise.displayName.trimmingCharacters(in: .whitespaces).isEmpty,
                    "\(exercise.id) has no display name")
        }
    }

    @Test("Every entry has at least one primary muscle")
    func primaryMusclesPresent() throws {
        for exercise in try loaded().all {
            #expect(!exercise.primaryMuscles.isEmpty, "\(exercise.id) has no primary muscle")
        }
    }

    @Test("Every taxonomy value in the catalog is one this build recognizes")
    func taxonomiesRecognized() throws {
        for exercise in try loaded().all {
            #expect(exercise.equipment.isKnown, "\(exercise.id): unknown equipment \(exercise.equipment)")
            #expect(exercise.pattern.isKnown, "\(exercise.id): unknown pattern \(exercise.pattern)")
            #expect(exercise.category.isKnown, "\(exercise.id): unknown category \(exercise.category)")
            for muscle in exercise.primaryMuscles + exercise.secondaryMuscles {
                #expect(muscle.isKnown, "\(exercise.id): unknown muscle \(muscle)")
            }
        }
    }

    @Test("A muscle is never both primary and secondary for one exercise")
    func musclesDoNotOverlap() throws {
        for exercise in try loaded().all {
            #expect(Set(exercise.primaryMuscles).isDisjoint(with: Set(exercise.secondaryMuscles)),
                    "\(exercise.id) repeats a muscle")
        }
    }

    @Test("Enough of the catalog is resistance training to build plans from")
    func resistanceCoverage() throws {
        let resistance = try loaded().all.filter(\.isResistanceTraining)
        #expect(resistance.count > 300, "only \(resistance.count) resistance exercises")
    }

    @Test("Every resistance movement pattern has at least one bodyweight option")
    func bodyweightCoverage() throws {
        let loaded = try loaded()
        for pattern in [MovementPattern.squat, .hinge, .horizontalPress, .verticalPull] {
            let filter = ExerciseFilter(equipment: [.bodyweight], patterns: [pattern])
            #expect(!loaded.exercises(matching: filter).isEmpty,
                    "no bodyweight option for \(pattern)")
        }
    }

    @Test("Every catalog entry resolves to itself by display name")
    func everyEntryResolves() throws {
        let loaded = try loaded()
        let resolver = ExerciseResolver(catalog: loaded)
        for exercise in loaded.all {
            let resolved = resolver.resolve(exercise.displayName)
            #expect(resolved?.id == exercise.id, "\(exercise.id) did not resolve to itself")
        }
    }
}
