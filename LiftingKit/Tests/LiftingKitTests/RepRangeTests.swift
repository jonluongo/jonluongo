import Testing
import Foundation
@testable import LiftingKit

@Suite("RepRange")
struct RepRangeTests {

    @Test("A hyphenated range parses lower and upper bounds")
    func hyphenatedRange() {
        let range = RepRange("8-12")
        #expect(range.lowerBound == 8)
        #expect(range.upperBound == 12)
    }

    @Test("A single number is both bounds")
    func singleNumber() {
        let range = RepRange("5")
        #expect(range.lowerBound == 5)
        #expect(range.upperBound == 5)
    }

    @Test("A reversed range is normalized so lowerBound <= upperBound")
    func reversedRangeIsNormalized() {
        let range = RepRange("12-8")
        #expect(range.lowerBound == 8)
        #expect(range.upperBound == 12)
    }

    @Test("Empty text has zero bounds and is empty")
    func emptyText() {
        let range = RepRange("")
        #expect(range.lowerBound == 0)
        #expect(range.upperBound == 0)
        #expect(range.isEmpty)
    }

    @Test("Text with no digits has zero bounds and is empty")
    func noDigits() {
        let range = RepRange("AMRAP")
        #expect(range.lowerBound == 0)
        #expect(range.upperBound == 0)
        #expect(range.isEmpty)
    }

    @Test("Words and punctuation between numbers are ignored")
    func wordsAsSeparator() {
        let range = RepRange("8 to 12")
        #expect(range.lowerBound == 8)
        #expect(range.upperBound == 12)
    }

    @Test("An en dash separates bounds just like a hyphen")
    func enDashSeparator() {
        let range = RepRange("8\u{2013}12")
        #expect(range.lowerBound == 8)
        #expect(range.upperBound == 12)
    }

    @Test("Three or more numbers use the first as lower and the last as upper")
    func threeNumbers() {
        let range = RepRange("5-3-1")
        #expect(range.lowerBound == 1)
        #expect(range.upperBound == 5)
    }

    @Test("A non-empty range is not empty")
    func nonEmptyRangeIsNotEmpty() {
        #expect(!RepRange("8-12").isEmpty)
    }

    @Test("description gives back a readable form")
    func descriptionIsReadable() {
        #expect(RepRange("8-12").description == "8-12")
        #expect(RepRange("5").description == "5")
    }

    @Test(
        "lowerBound is never greater than upperBound",
        arguments: ["8-12", "12-8", "5", "", "AMRAP", "8 to 12", "8\u{2013}12", "5-3-1", "1-3-5", "100-1"]
    )
    func lowerNeverExceedsUpper(text: String) {
        let range = RepRange(text)
        #expect(range.lowerBound <= range.upperBound)
    }

    @Test("RepRange is Codable and round-trips through JSON")
    func codableRoundTrips() throws {
        let original = RepRange("8-12")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RepRange.self, from: data)
        #expect(decoded == original)
    }
}
