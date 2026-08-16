import Foundation
import Testing

@testable import LiftingKit

/// The two facts that had no write path at all: what the lifter weighs, and what
/// he could already do on a lift before any history existed.
///
/// Both are series rather than numbers, and the assertions here are about that:
/// a second reading on a new day must not replace the first, while a second
/// reading on the same day must, because that is a correction.
@Suite("Bodyweight and baselines")
struct ProfileFactsTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let earlierDay = Date(timeIntervalSince1970: 1_699_000_000)

    private func update(
        bodyweight: [BodyweightReading] = [],
        baselines: [BaselineStatement] = []
    ) -> ProfileUpdate {
        ProfileUpdate(
            id: UUID(), generatedAt: Self.instant,
            bodyweight: bodyweight, baselines: baselines
        )
    }

    private func roundTrip(_ update: ProfileUpdate) throws -> ProfileUpdate {
        let data = try ProfileUpdate.makeEncoder().encode(update)
        return try ProfileUpdate.makeDecoder().decode(ProfileUpdate.self, from: data)
    }

    // MARK: - A reading survives the trip

    @Test("A bodyweight reading round-trips with its date and its unit intact")
    func readingRoundTrips() throws {
        let reading = BodyweightReading(
            date: Self.earlierDay, mass: Mass(value: 182.5, unit: .pounds))

        let decoded = try roundTrip(update(bodyweight: [reading]))

        #expect(decoded.bodyweight == [reading])
        #expect(decoded.bodyweight.first?.mass.unit == .pounds)
    }

    @Test("Two readings on different days are two points, not one overwritten")
    func twoDaysAreASeries() throws {
        let series = [
            BodyweightReading(date: Self.earlierDay, mass: Mass(value: 178, unit: .pounds)),
            BodyweightReading(date: Self.instant, mass: Mass(value: 182, unit: .pounds)),
        ]

        #expect(try roundTrip(update(bodyweight: series)).bodyweight == series)
    }

    @Test("A reading that names no day reads as the day the update was written")
    func undatedReadingFallsBackToTheDocument() {
        let reading = BodyweightReading(date: nil, mass: Mass(value: 182, unit: .pounds))

        #expect(reading.resolvedDate(from: Self.instant) == Self.instant)
        #expect(
            BodyweightReading(date: Self.earlierDay, mass: Mass(value: 182, unit: .pounds))
                .resolvedDate(from: Self.instant) == Self.earlierDay)
    }

    @Test("A baseline round-trips with a bodyweight load left absent rather than zeroed")
    func baselineRoundTrips() throws {
        let statements = [
            BaselineStatement(
                exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
                load: Mass(value: 205, unit: .pounds), reps: 5, recordedAt: Self.earlierDay),
            BaselineStatement(
                exerciseID: ExerciseID(rawValue: "pull-up"), load: nil, reps: 8, recordedAt: nil),
        ]

        let decoded = try roundTrip(update(baselines: statements))

        #expect(decoded.baselines == statements)
        #expect(decoded.baselines.last?.load == nil, "a bodyweight baseline is not a zero one")
    }

    // MARK: - What is refused

    @Test("A key inside a reading that this format does not have is refused by name")
    func unknownKeyInsideAReadingIsRefused() {
        let json = """
            {"version": 2, "id": "11111111-2222-3333-4444-555555555555",
             "generatedAt": "2023-11-14T22:13:20Z",
             "bodyweight": [{"mass": {"value": 182, "unit": "lb"}, "bodyFat": 14}]}
            """

        #expect(throws: DocumentRefusal.self) {
            try ProfileUpdate.makeDecoder().decode(ProfileUpdate.self, from: Data(json.utf8))
        }
    }

    @Test("A series cannot be taken back with a null, and says so rather than dropping it")
    func nullSeriesIsRefused() {
        // Read as "no readings", this would report success while the fact
        // Claude meant to correct stayed exactly as it was.
        let json = """
            {"version": 2, "id": "11111111-2222-3333-4444-555555555555",
             "generatedAt": "2023-11-14T22:13:20Z", "bodyweight": null}
            """

        #expect(throws: DocumentRefusal.self) {
            try ProfileUpdate.makeDecoder().decode(ProfileUpdate.self, from: Data(json.utf8))
        }
    }

    // MARK: - Folding two updates

    @Test("Readings from an update the phone has not seen survive the next one")
    func foldingKeepsBothDays() {
        let earlier = update(bodyweight: [
            BodyweightReading(date: Self.earlierDay, mass: Mass(value: 178, unit: .pounds))
        ])
        let later = update(bodyweight: [
            BodyweightReading(date: Self.instant, mass: Mass(value: 182, unit: .pounds))
        ])

        let folded = later.superseding(earlier)

        #expect(folded.bodyweight.count == 2)
        #expect(folded.bodyweight.first?.date == Self.earlierDay)
    }

    @Test("Two readings for the same day fold to the later one, which is the correction")
    func foldingCorrectsTheSameDay() {
        let earlier = update(bodyweight: [
            BodyweightReading(date: Self.earlierDay, mass: Mass(value: 178, unit: .pounds))
        ])
        let later = update(bodyweight: [
            BodyweightReading(date: Self.earlierDay, mass: Mass(value: 179, unit: .pounds))
        ])

        let folded = later.superseding(earlier)

        #expect(folded.bodyweight.count == 1)
        #expect(folded.bodyweight.first?.mass.value == 179)
    }

    @Test("A baseline folds on the lift it is about, since a lift has one starting point")
    func foldingReplacesABaselineForTheSameLift() {
        let bench = ExerciseID(rawValue: "barbell-bench-press")
        let squat = ExerciseID(rawValue: "barbell-squat")
        let earlier = update(baselines: [
            BaselineStatement(exerciseID: bench, load: nil, reps: 5, recordedAt: nil),
            BaselineStatement(exerciseID: squat, load: nil, reps: 5, recordedAt: nil),
        ])
        let later = update(baselines: [
            BaselineStatement(
                exerciseID: bench, load: Mass(value: 205, unit: .pounds), reps: 3,
                recordedAt: nil)
        ])

        let folded = later.superseding(earlier)

        #expect(folded.baselines.count == 2)
        #expect(folded.baselines.first(where: { $0.exerciseID == bench })?.reps == 3)
        #expect(folded.baselines.first(where: { $0.exerciseID == squat })?.reps == 5)
    }

    @Test("An update carrying only a reading is not an update that states nothing")
    func aReadingIsAStatedFact() {
        #expect(!update(bodyweight: [
            BodyweightReading(date: nil, mass: Mass(value: 182, unit: .pounds))
        ]).statesNothing)
        #expect(!update(baselines: [
            BaselineStatement(
                exerciseID: ExerciseID(rawValue: "pull-up"), load: nil, reps: 8, recordedAt: nil)
        ]).statesNothing)
        #expect(update().statesNothing)
    }
}
