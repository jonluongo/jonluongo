import Testing
import Foundation
@testable import LiftingKit

/// Reading a carry out of the text a plan wrote it in, and keeping it apart
/// from the two measures that already had readers.
///
/// The pairing with `RepRangeTests` and `WorkDurationTests` is the point: a
/// farmer's carry written as `"40 metres"` must be refused by both of them and
/// read by this one, and no target anywhere may be claimed by two. The last
/// suite here asserts exactly that, across all three.
@Suite("WorkDistance")
struct WorkDistanceTests {

    // MARK: - What is a distance

    @Test(
        "A target measured in distance is recognized as one",
        arguments: [
            "40 metres", "40 m", "40m", "50 yards", "20 ft", "1 km", "100 METRES",
            "40 metre carry", "2 lengths of 20 yards",
        ]
    )
    func distanceTargetsAreRecognized(text: String) {
        #expect(WorkDistance(text).isDistance, "\(text) prescribes a distance")
    }

    @Test(
        "A rep target is not a distance",
        arguments: ["8-12", "5", "AMRAP", "", "8 to 12", "10 each side", "5RM"]
    )
    func repTargetsAreNotDistances(text: String) {
        #expect(!WorkDistance(text).isDistance, "\(text) prescribes repetitions")
    }

    @Test(
        "A hold is not a distance",
        arguments: ["30 seconds", "1:30", "2 min", "max time hold", "40 m in 30 seconds"]
    )
    func holdsAreNotDistances(text: String) {
        #expect(!WorkDistance(text).isDistance, "\(text) is claimed by the clock")
    }

    // MARK: - How far it says, in the unit it says it in

    @Test("A distance is read as its number and the unit it was written in")
    func distanceIsRead() {
        #expect(WorkDistance("40 metres").distance == Distance(value: 40, unit: .metres))
        #expect(WorkDistance("50 yards").distance == Distance(value: 50, unit: .yards))
        #expect(WorkDistance("20 ft").distance == Distance(value: 20, unit: .feet))
    }

    @Test("Yards stay yards — nothing is converted into anything else")
    func nothingIsConverted() {
        let carried = WorkDistance("50 yards")

        #expect(carried.distance?.unit == .yards)
        #expect(carried.distance?.value == 50, "fifty yards is not forty-five point seven metres")
    }

    @Test(
        "Every spelling of one unit is that one unit",
        arguments: ["40 m", "40 meter", "40 meters", "40 metre", "40 metres"]
    )
    func spellingsAgree(text: String) {
        #expect(WorkDistance(text).distance == Distance(value: 40, unit: .metres))
    }

    @Test("A range of distances states both bounds and seeds neither")
    func rangeStatesBothBounds() {
        let range = WorkDistance("50-100 yd")

        #expect(range.isDistance)
        #expect(range.unit == .yards)
        #expect(range.lowerValue == 50)
        #expect(range.upperValue == 100)
        #expect(range.distance == nil, "a range names no single distance to seed")
    }

    @Test("A reversed range is normalized")
    func reversedRangeIsNormalized() {
        let range = WorkDistance("100-50 m")

        #expect(range.lowerValue == 50)
        #expect(range.upperValue == 100)
    }

    @Test("A carry this build cannot put one number on is still a carry")
    func unreadableDistanceIsStillADistance() {
        let mixed = WorkDistance("40 m then 20 yd")

        #expect(mixed.isDistance)
        #expect(mixed.distance == nil, "two units name no one distance")
        #expect(mixed.unit == .metres, "the unit it opens in is what it is measured in")
    }

    @Test("A rep target reads as no distance at all")
    func repTargetHasNoDistance() {
        let carried = WorkDistance("8-12")

        #expect(carried.isEmpty)
        #expect(carried.distance == nil)
        #expect(carried.unit == nil)
        #expect(carried.description == "")
    }

    @Test("description gives back a readable form")
    func descriptionIsReadable() {
        #expect(WorkDistance("40 metres").description == "40 m")
        #expect(WorkDistance("50-100 yd").description == "50-100 yd")
    }

    // MARK: - The measure a prescription names

    @Test("A prescription names exactly one of the things a set can be measured in")
    func measureIsNamed() {
        #expect(WorkMeasure("8-12") == .repetitions)
        #expect(WorkMeasure("AMRAP") == .repetitions)
        #expect(WorkMeasure("") == .repetitions)
        #expect(WorkMeasure("30 seconds") == .time)
        #expect(WorkMeasure("1:30") == .time)
        #expect(WorkMeasure("40 metres") == .distance(.metres))
        #expect(WorkMeasure("50 yd") == .distance(.yards))
    }

    // MARK: - No two readers claim one target

    @Test(
        "No target is read as more than one kind of work",
        arguments: [
            "8-12", "5", "AMRAP", "", "30 seconds", "1:30", "2 min", "40 m",
            "40 metres", "50 yards", "20 ft", "8 to 12", "30-45 seconds",
            "10 each side", "max time hold", "40 m in 30 seconds",
        ]
    )
    func onlyOneReaderClaimsATarget(text: String) {
        let claimed = [
            !RepRange(text).isEmpty, WorkDuration(text).isTimed, WorkDistance(text).isDistance,
        ].filter { $0 }

        #expect(claimed.count <= 1, "'\(text)' was claimed by \(claimed.count) readers")
    }

    @Test(
        "Every target a distance reads is one RepRange refuses",
        arguments: ["40 m", "40 metres", "50 yards", "20 ft", "1 km", "5 miles"]
    )
    func distanceTargetsAreRefusedAsReps(text: String) {
        #expect(RepRange(text).isEmpty, "'\(text)' names no rep count")
        #expect(WorkDistance(text).isDistance)
    }

    // MARK: - A unit nobody here thought of

    @Test("A unit this build has never heard of round-trips intact")
    func unknownUnitRoundTrips() throws {
        let stated = Distance(value: 3, unit: DistanceUnit(rawValue: "furlong"))
        let data = try JSONEncoder().encode(stated)

        #expect(try JSONDecoder().decode(Distance.self, from: data) == stated)
        #expect(!stated.unit.isKnown, "this build has never heard of it")
        #expect(String(decoding: data, as: UTF8.self).contains("furlong"))
    }

    @Test("A distance written by hand decodes as what it says")
    func handWrittenDistanceDecodes() throws {
        let decoded = try JSONDecoder().decode(
            Distance.self, from: Data(#"{"value": 40, "unit": "m"}"#.utf8))

        #expect(decoded == Distance(value: 40, unit: .metres))
    }
}
