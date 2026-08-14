import Testing
import Foundation
@testable import LiftingPlan

@Suite("Mass")
struct MassTests {

    @Test("Pounds convert to kilograms")
    func poundsToKilograms() {
        let mass = Mass(value: 100, unit: .pounds)
        #expect(abs(mass.kilograms - 45.359237) < 0.000001)
    }

    @Test("Kilograms convert to pounds")
    func kilogramsToPounds() {
        let mass = Mass(value: 100, unit: .kilograms)
        #expect(abs(mass.pounds - 220.462262) < 0.000001)
    }

    @Test("A mass in its own unit returns its value unchanged")
    func sameUnitIsExact() {
        #expect(Mass(value: 135, unit: .pounds).pounds == 135)
        #expect(Mass(value: 60, unit: .kilograms).kilograms == 60)
    }

    @Test("Equality is exact on representation, so a logbook never rewrites entries")
    func equalityIsRepresentational() {
        let inPounds = Mass(value: 100, unit: .pounds)
        let inKilograms = inPounds.converted(to: .kilograms)
        #expect(inPounds != inKilograms)
        #expect(abs(inPounds.kilograms - inKilograms.kilograms) < 0.000001)
    }

    @Test("Converting round-trip returns to the original value")
    func roundTrip() {
        let original = Mass(value: 137.5, unit: .pounds)
        let back = original.converted(to: .kilograms).converted(to: .pounds)
        #expect(abs(back.value - original.value) < 0.000001)
    }

    @Test("Rounding snaps to the nearest plate increment")
    func rounding() {
        #expect(Mass(value: 134.9998, unit: .pounds).rounded(toNearest: 2.5).value == 135)
        #expect(Mass(value: 61.3, unit: .kilograms).rounded(toNearest: 1.25).value == 61.25)
    }

    @Test("A mass encodes and decodes with its unit intact")
    func codableKeepsUnit() throws {
        let original = Mass(value: 225, unit: .pounds)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Mass.self, from: data)
        #expect(decoded == original)
    }
}
