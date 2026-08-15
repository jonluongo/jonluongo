import Testing
import Foundation
@testable import LiftingKit

@Suite("Exercise resolver")
struct ExerciseResolverTests {

    private func make(
        _ id: String, _ name: String, aliases: [String] = [],
        pattern: MovementPattern = .horizontalPress,
        equipment: EquipmentType = .barbell,
        muscles: [MuscleGroup] = [.chest]
    ) -> Exercise {
        Exercise(
            id: ExerciseID(rawValue: id), displayName: name, aliases: aliases,
            primaryMuscles: muscles, secondaryMuscles: [], equipment: equipment,
            pattern: pattern, force: nil, mechanic: .compound,
            category: .strength, instructions: [], mediaAsset: nil
        )
    }

    private var resolver: ExerciseResolver {
        ExerciseResolver(catalog: ExerciseCatalog(exercises: [
            make("barbell-bench-press", "Barbell Bench Press", aliases: ["flat bench press"]),
            make("dumbbell-bench-press", "Dumbbell Bench Press", equipment: .dumbbell),
            make("barbell-squat", "Barbell Squat", pattern: .squat, muscles: [.quadriceps]),
            make("push-up", "Push Up", equipment: .bodyweight),
        ]))
    }

    @Test("An exact display name resolves with exact confidence")
    func exactName() throws {
        let result = try #require(resolver.resolve("Barbell Bench Press"))
        #expect(result.id == ExerciseID(rawValue: "barbell-bench-press"))
        #expect(result.confidence == .exact)
    }

    @Test("A raw slug resolves exactly")
    func exactSlug() throws {
        let result = try #require(resolver.resolve("barbell-bench-press"))
        #expect(result.id == ExerciseID(rawValue: "barbell-bench-press"))
    }

    @Test("An alias resolves to its exercise")
    func alias() throws {
        let result = try #require(resolver.resolve("flat bench press"))
        #expect(result.id == ExerciseID(rawValue: "barbell-bench-press"))
        #expect(result.confidence == .alias)
    }

    @Test("Word order and punctuation do not defeat matching")
    func normalized() throws {
        let result = try #require(resolver.resolve("Bench Press (Barbell)"))
        #expect(result.id == ExerciseID(rawValue: "barbell-bench-press"))
        #expect(result.confidence == .normalized)
    }

    @Test("Casing and extra whitespace do not defeat matching")
    func casing() throws {
        let result = try #require(resolver.resolve("  BARBELL   SQUAT  "))
        #expect(result.id == ExerciseID(rawValue: "barbell-squat"))
    }

    @Test("A near miss resolves by fuzzy match")
    func fuzzy() throws {
        let result = try #require(resolver.resolve("Barbel Bench Pres"))
        #expect(result.id == ExerciseID(rawValue: "barbell-bench-press"))
        if case .fuzzy = result.confidence {} else {
            Issue.record("expected fuzzy confidence, got \(result.confidence)")
        }
    }

    @Test("Nonsense resolves to nothing rather than to a wrong exercise")
    func unresolvable() {
        #expect(resolver.resolve("quantum tesseract press") == nil)
        #expect(resolver.resolve("") == nil)
    }

    @Test("With a fallback filter, an unresolvable name still yields a real exercise")
    func fallbackSubstitutes() throws {
        let filter = ExerciseFilter(patterns: [.squat])
        let result = try #require(resolver.resolve("quantum tesseract press", fallback: filter))
        #expect(result.id == ExerciseID(rawValue: "barbell-squat"))
        #expect(result.confidence == .fallback)
    }

    @Test("A fallback that matches nothing still refuses to invent an exercise")
    func fallbackImpossible() {
        let filter = ExerciseFilter(equipment: [.kettlebell])
        #expect(resolver.resolve("nonsense", fallback: filter) == nil)
    }

    @Test("Every resolution points at an exercise that exists in the catalog")
    func resolutionsAreReal() throws {
        let catalog = ExerciseCatalog(exercises: [
            make("barbell-bench-press", "Barbell Bench Press"),
        ])
        let resolver = ExerciseResolver(catalog: catalog)
        for probe in ["Barbell Bench Press", "bench press barbell", "Barbel Bench Pres"] {
            let resolved = try #require(resolver.resolve(probe), "\(probe) did not resolve")
            #expect(catalog.exercise(id: resolved.id) != nil)
        }
    }
}
