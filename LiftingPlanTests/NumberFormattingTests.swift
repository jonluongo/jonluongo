import Testing
@testable import LiftingPlan

@Suite("Number formatting")
struct NumberFormattingTests {

    @Test("Whole numbers lose their trailing .0, fractions keep one digit")
    func compactString() {
        #expect(135.0.compactString == "135")
        #expect(0.0.compactString == "0")
        #expect(62.5.compactString == "62.5")
        #expect(7.25.compactString == "7.2")   // display only — one decimal shown
        #expect((-45.0).compactString == "-45")
    }
}
