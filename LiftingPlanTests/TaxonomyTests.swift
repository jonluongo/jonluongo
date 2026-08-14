import Testing
import Foundation
@testable import LiftingPlan

@Suite("Extensible taxonomies")
struct TaxonomyTests {

    @Test("A known value decodes to its static constant")
    func knownValueDecodes() throws {
        let decoded = try JSONDecoder().decode(MuscleGroup.self, from: Data("\"chest\"".utf8))
        #expect(decoded == MuscleGroup.chest)
    }

    @Test("An unknown value survives decoding instead of failing")
    func unknownValueSurvives() throws {
        let decoded = try JSONDecoder().decode(MuscleGroup.self, from: Data("\"serratus\"".utf8))
        #expect(decoded.rawValue == "serratus")
    }

    @Test("An unknown value round-trips through encoding unchanged")
    func unknownValueRoundTrips() throws {
        let original = MuscleGroup(rawValue: "serratus")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MuscleGroup.self, from: data)
        #expect(decoded == original)
        #expect(String(decoding: data, as: UTF8.self) == "\"serratus\"")
    }

    @Test("Values are canonicalized so casing and padding do not fragment identity")
    func canonicalization() {
        #expect(MuscleGroup(rawValue: "  CHEST ") == MuscleGroup.chest)
        #expect(EquipmentType(rawValue: "Barbell") == EquipmentType.barbell)
    }

    @Test("Each taxonomy exposes its known values for UI and validation")
    func knownValuesExposed() {
        #expect(MuscleGroup.known.contains(MuscleGroup.chest))
        #expect(EquipmentType.known.contains(EquipmentType.bodyweight))
        #expect(!MuscleGroup.known.contains(MuscleGroup(rawValue: "serratus")))
    }

    @Test("Difficulty decodes known values and preserves unknown ones")
    func difficultyTaxonomy() throws {
        #expect(try JSONDecoder().decode(Difficulty.self, from: Data("\"advanced\"".utf8)) == .advanced)
        let exotic = try JSONDecoder().decode(Difficulty.self, from: Data("\"elite\"".utf8))
        #expect(exotic.rawValue == "elite")
        #expect(!exotic.isKnown)
    }
}
