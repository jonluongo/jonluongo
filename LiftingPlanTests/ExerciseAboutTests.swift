import Testing
import Foundation
@testable import LiftingPlan
import LiftingKit

/// The info screen prints what the catalog holds and nothing it does not.
///
/// An entry that was never graded, or that names no secondary muscles, must
/// produce no row at all rather than a row reading "unknown" — a screen that
/// fills its gaps is a screen that has started making things up about a
/// movement, and 82% of the catalog has no instructions to show.
@Suite("Exercise about")
struct ExerciseAboutTests {

    /// Catalog entries have no public initializer by design, so a fixture is
    /// decoded exactly the way the bundled file is.
    private func exercise(_ json: String) throws -> Exercise {
        try JSONDecoder().decode(Exercise.self, from: Data(json.utf8))
    }

    private let full = """
        {
          "id": "barbell-bench-press", "displayName": "Barbell Bench Press",
          "primaryMuscles": ["chest"], "secondaryMuscles": ["triceps", "shoulders"],
          "equipment": "barbell", "pattern": "horizontal press", "category": "strength",
          "mechanic": "compound", "difficulty": "intermediate",
          "instructions": ["Unrack the bar.", "Lower it to the chest."]
        }
        """

    private let sparse = """
        {
          "id": "abdominals-stretch-variation-four",
          "displayName": "Abdominals Stretch Variation Four",
          "primaryMuscles": ["abdominals"], "equipment": "bodyweight",
          "pattern": "stretch", "category": "stretching"
        }
        """

    @Test("Everything the entry states, in reading order")
    func statedFacts() throws {
        let facts = ExerciseAbout.facts(for: try exercise(full))
        #expect(facts.map(\.label) == [
            "Primary", "Also works", "Equipment", "Pattern", "Mechanic", "Difficulty",
        ])
        #expect(facts.map(\.value) == [
            "Chest", "Triceps, Shoulders", "Barbell", "Horizontal press",
            "Compound", "Intermediate",
        ])
    }

    @Test("An entry that says nothing about a thing gets no row for it")
    func absenceIsAbsence() throws {
        let facts = ExerciseAbout.facts(for: try exercise(sparse))
        #expect(facts.map(\.label) == ["Primary", "Equipment", "Pattern"])
        #expect(!facts.contains { $0.label == "Difficulty" })
        #expect(!facts.contains { $0.label == "Also works" })
    }

    @Test("An entry with no instructions has none to show")
    func noInstructions() throws {
        // The view draws the heading only when this is non-empty, which is what
        // keeps four in five exercises from showing an empty "How to perform it".
        #expect(try exercise(sparse).instructions.isEmpty)
        #expect(try exercise(full).instructions.count == 2)
    }

    @Test("No fact is ever printed empty")
    func noEmptyValues() throws {
        for entry in [try exercise(full), try exercise(sparse)] {
            #expect(ExerciseAbout.facts(for: entry).allSatisfy { !$0.value.isEmpty })
        }
    }

    @Test("A muscle this build has never heard of is still what the data says")
    func unknownTaxonomyValueSurvives() throws {
        // The taxonomies are open on purpose; a newer catalog naming a muscle
        // this build does not know must read it out rather than drop it.
        let entry = try exercise("""
            {
              "id": "psoas-march", "displayName": "Psoas March",
              "primaryMuscles": ["hip flexors"], "equipment": "band",
              "pattern": "flexion", "category": "strength"
            }
            """)
        let primary = try #require(ExerciseAbout.facts(for: entry).first)
        #expect(primary.value == "Hip flexors")
    }
}
