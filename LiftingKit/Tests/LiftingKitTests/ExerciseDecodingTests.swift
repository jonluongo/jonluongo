import Testing
import Foundation
@testable import LiftingKit

@Suite("Exercise decoding")
struct ExerciseDecodingTests {

    @Test("A complete entry decodes every field")
    func fullEntry() throws {
        let json = """
        {
          "id": "barbell-bench-press",
          "displayName": "Barbell Bench Press",
          "aliases": ["bench press", "flat bench"],
          "primaryMuscles": ["chest"],
          "secondaryMuscles": ["triceps", "shoulders"],
          "equipment": "barbell",
          "pattern": "horizontal press",
          "force": "push",
          "mechanic": "compound",
          "category": "strength",
          "instructions": ["Lie on the bench.", "Press the bar."]
        }
        """
        let exercise = try JSONDecoder().decode(Exercise.self, from: Data(json.utf8))
        #expect(exercise.id == ExerciseID(rawValue: "barbell-bench-press"))
        #expect(exercise.displayName == "Barbell Bench Press")
        #expect(exercise.primaryMuscles == [.chest])
        #expect(exercise.secondaryMuscles == [.triceps, .shoulders])
        #expect(exercise.equipment == .barbell)
        #expect(exercise.mechanic == .compound)
        #expect(exercise.instructions.count == 2)
        #expect(exercise.mediaAsset == nil)
    }

    @Test("Absent optional collections default to empty rather than failing")
    func minimalEntry() throws {
        let json = """
        {
          "id": "burpee",
          "displayName": "Burpee",
          "primaryMuscles": ["quadriceps"],
          "equipment": "bodyweight",
          "pattern": "plyometric",
          "category": "plyometrics"
        }
        """
        let exercise = try JSONDecoder().decode(Exercise.self, from: Data(json.utf8))
        #expect(exercise.aliases.isEmpty)
        #expect(exercise.secondaryMuscles.isEmpty)
        #expect(exercise.instructions.isEmpty)
        #expect(exercise.force == nil)
        #expect(exercise.mechanic == nil)
    }

    @Test("An entry that does not grade its difficulty is ungraded, not intermediate")
    func ungradedDifficultyStaysAbsent() throws {
        let json = """
        {
          "id": "burpee",
          "displayName": "Burpee",
          "primaryMuscles": ["quadriceps"],
          "equipment": "bodyweight",
          "pattern": "plyometric",
          "category": "plyometrics"
        }
        """
        let exercise = try JSONDecoder().decode(Exercise.self, from: Data(json.utf8))
        #expect(exercise.difficulty == nil)
    }

    @Test("A stated difficulty is carried, including one this build does not know")
    func statedDifficultyIsCarried() throws {
        func decode(_ stated: String) throws -> Difficulty? {
            let json = """
            {
              "id": "power-clean", "displayName": "Power Clean",
              "primaryMuscles": ["quadriceps"], "equipment": "barbell",
              "pattern": "olympic", "category": "olympic weightlifting",
              "difficulty": "\(stated)"
            }
            """
            return try JSONDecoder().decode(Exercise.self, from: Data(json.utf8)).difficulty
        }
        #expect(try decode("advanced") == .advanced)
        #expect(try decode("elite")?.rawValue == "elite")
    }

    @Test("Unknown keys are ignored so a newer catalog does not break an older build")
    func unknownKeysIgnored() throws {
        let json = """
        {
          "id": "z-press",
          "displayName": "Z Press",
          "primaryMuscles": ["shoulders"],
          "equipment": "barbell",
          "pattern": "vertical press",
          "category": "strength",
          "difficultyScore": 7,
          "introducedIn": "2027.1"
        }
        """
        let exercise = try JSONDecoder().decode(Exercise.self, from: Data(json.utf8))
        #expect(exercise.id == ExerciseID(rawValue: "z-press"))
    }

    @Test("An entry missing its identity fails loudly")
    func missingIdentityThrows() {
        let json = """
        { "displayName": "Nameless", "primaryMuscles": ["chest"],
          "equipment": "barbell", "pattern": "squat", "category": "strength" }
        """
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Exercise.self, from: Data(json.utf8))
        }
    }

    @Test("Search text includes the display name and every alias")
    func searchText() throws {
        let exercise = Exercise(
            id: ExerciseID(rawValue: "barbell-bench-press"),
            displayName: "Barbell Bench Press",
            aliases: ["flat bench"],
            primaryMuscles: [.chest],
            secondaryMuscles: [],
            equipment: .barbell,
            pattern: .horizontalPress,
            force: .push,
            mechanic: .compound,
            category: .strength,
            instructions: [],
            mediaAsset: nil
        )
        #expect(exercise.searchText.contains("barbell bench press"))
        #expect(exercise.searchText.contains("flat bench"))
    }
}
