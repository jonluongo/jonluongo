import Testing
import Foundation
@testable import LiftingKit

/// What one prescribed set states, and what the format refuses.
///
/// **This suite replaced one twice its size.** `SetPrescriptionTests` spent half
/// its length on machinery that no longer exists: an exercise's `sets` being
/// either a count or a list, a listed set inheriting the exercise's rep range
/// and load, a per-set intensity *overriding* the exercise's. Every prescribed
/// set is a row now, so there are no defaults to override and no second code
/// path — and the tests that guarded the reconciliation went with it. What
/// survives is what was always the point: a load written is a load stored, an
/// intensity is carried on the scale it was stated on, and a key this format
/// does not have is refused with the key named.
@Suite("What one prescribed set states")
struct PlanDocumentSetTests {

    private let squat = ExerciseID(rawValue: "barbell-back-squat")

    private func document(_ sets: [PlanDocumentSet]) -> PlanDocument {
        PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sessions: [
                PlanDocumentSession(
                    blockOrdinal: 1, ordinal: 1, focus: "Lower",
                    entries: [
                        .exercise(PlanDocumentExercise(
                            exerciseID: squat, displayName: "Squat", sets: sets))
                    ])
            ])
    }

    private func roundTrip(_ document: PlanDocument) throws -> PlanDocument {
        let data = try PlanDocument.makeEncoder().encode(document)
        return try PlanDocument.makeDecoder().decode(PlanDocument.self, from: data)
    }

    private func sets(in document: PlanDocument) throws -> [PlanDocumentSet] {
        let session = try #require(document.sessions.first)
        let exercise = try #require(session.entries.first?.exercises.first)
        return exercise.sets
    }

    private func decoded(_ json: String) throws -> PlanDocument {
        try PlanDocument.makeDecoder().decode(PlanDocument.self, from: Data(json.utf8))
    }

    private func kilos(_ value: Double) -> Mass { Mass(value: value, unit: .kilograms) }

    // MARK: - Loads, exactly as written

    @Test("A drop set is the sets it is: three at one load and a fourth lower")
    func dropSetKeepsEveryLoad() throws {
        let decoded = try roundTrip(document([
            PlanDocumentSet(target: .repetitions(low: 8, high: nil), load: kilos(100)),
            PlanDocumentSet(target: .repetitions(low: 8, high: nil), load: kilos(100)),
            PlanDocumentSet(target: .repetitions(low: 8, high: nil), load: kilos(100)),
            PlanDocumentSet(target: .repetitionsToFailure, load: kilos(70)),
        ]))

        let sets = try sets(in: decoded)
        #expect(sets.map { $0.load?.value } == [100, 100, 100, 70])
        #expect(sets.last?.target == .repetitionsToFailure)
    }

    @Test("A ramp keeps its loads in the order they were written")
    func rampKeepsItsOrder() throws {
        let decoded = try roundTrip(document([
            PlanDocumentSet(load: kilos(60)), PlanDocumentSet(load: kilos(80)),
            PlanDocumentSet(load: kilos(100)), PlanDocumentSet(load: kilos(110)),
        ]))
        #expect(try sets(in: decoded).map { $0.load?.value } == [60, 80, 100, 110])
    }

    @Test("A load keeps the unit it was written in")
    func aLoadKeepsItsUnit() throws {
        let decoded = try roundTrip(document([
            PlanDocumentSet(load: Mass(value: 225, unit: .pounds)),
            PlanDocumentSet(load: kilos(100)),
        ]))
        let sets = try sets(in: decoded)
        #expect(sets.first?.load?.unit == .pounds)
        #expect(sets.last?.load?.unit == .kilograms)
    }

    @Test("A set with no load has none rather than a zero")
    func anAbsentLoadStaysAbsent() throws {
        // The lifter picks the bar when the coach states an intensity instead.
        // A zero here would be a prescription nobody wrote.
        let decoded = try roundTrip(document([
            PlanDocumentSet(
                target: .repetitions(low: 5, high: nil),
                intensity: IntensityTarget(scale: .rpe, value: "8"))
        ]))
        #expect(try sets(in: decoded).first?.load == nil)
    }

    @Test("An exercise that prescribes no sets prescribes none")
    func noSetsIsNoSets() throws {
        #expect(try sets(in: roundTrip(document([]))).isEmpty)
    }

    // MARK: - Warm-ups

    @Test("A warm-up the coach asked for survives as one")
    func aPrescribedWarmupSurvives() throws {
        // Before version 6 this could not be written at all: everything
        // prescribed was hardcoded as work, and only a set the lifter added
        // himself was ever marked. "Ramp three sets to your top set" had no
        // way of being said.
        let decoded = try roundTrip(document([
            PlanDocumentSet(load: kilos(60), isWarmup: true),
            PlanDocumentSet(load: kilos(80), isWarmup: true),
            PlanDocumentSet(target: .repetitions(low: 5, high: nil), load: kilos(100)),
        ]))
        #expect(try sets(in: decoded).map(\.isWarmup) == [true, true, false])
    }

    @Test("A working set carries no marker it does not need")
    func aWorkingSetWritesNothing() throws {
        let data = try PlanDocument.makeEncoder().encode(document([PlanDocumentSet()]))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("isWarmup"),
                "most sets are working sets; stating the default on each is noise")
    }

    // MARK: - Targets, read once

    @Test("Each measure survives as the measure it is")
    func everyMeasureSurvives() throws {
        let decoded = try roundTrip(document([
            PlanDocumentSet(target: .repetitions(low: 8, high: 12)),
            PlanDocumentSet(target: .time(low: 45, high: nil)),
            PlanDocumentSet(target: .distance(low: 40, high: nil, unit: .metres)),
            PlanDocumentSet(target: .repetitionsToFailure),
        ]))
        #expect(try sets(in: decoded).map(\.target) == [
            .repetitions(low: 8, high: 12), .time(low: 45, high: nil),
            .distance(low: 40, high: nil, unit: .metres), .repetitionsToFailure,
        ])
    }

    @Test("A carry stays a carry rather than reaching a rep total")
    func aCarryIsNeverCounted() throws {
        let decoded = try roundTrip(document([
            PlanDocumentSet(target: .distance(low: 40, high: nil, unit: .metres))
        ]))
        #expect(try sets(in: decoded).first?.target?.measure == .distance(.metres))
    }

    @Test("A set that states no target has none")
    func anAbsentTargetStaysAbsent() throws {
        #expect(try sets(in: roundTrip(document([PlanDocumentSet(load: kilos(100))])))
            .first?.target == nil)
    }

    // MARK: - Intensity, on whatever scale it was stated

    @Test("Every scale round-trips as the scale it was written on")
    func everyScaleSurvives() throws {
        let scales: [(IntensityScale, String, String)] = [
            (.rpe, "8", "rpe"),
            (.repsInReserve, "2", "rir"),
            (.percentOfOneRepMax, "80", "percent1RM"),
        ]
        for (scale, value, raw) in scales {
            let decoded = try roundTrip(document([
                PlanDocumentSet(intensity: IntensityTarget(scale: scale, value: value))
            ]))
            let intensity = try #require(try sets(in: decoded).first?.intensity)
            #expect(intensity.scale == scale, "\(raw)")
            #expect(intensity.value == value, "2 RIR is not 8 RPE unless a coach says so")
        }
    }

    @Test("An intensity stated as a range is carried whole, not resolved to an end")
    func anIntensityRangeIsCarriedWhole() throws {
        let decoded = try roundTrip(document([
            PlanDocumentSet(intensity: IntensityTarget(scale: .rpe, value: "8-9"))
        ]))
        #expect(try sets(in: decoded).first?.intensity?.value == "8-9")
    }

    @Test("A set with no intensity has none — not a zero and not a default")
    func anAbsentIntensityStaysAbsent() throws {
        #expect(try sets(in: roundTrip(document([PlanDocumentSet(load: kilos(100))])))
            .first?.intensity == nil)
    }

    @Test("A scale this build has never heard of round-trips intact")
    func anUnknownScaleSurvives() throws {
        let decoded = try roundTrip(document([
            PlanDocumentSet(
                intensity: IntensityTarget(scale: IntensityScale(rawValue: "watts"), value: "300"))
        ]))
        let intensity = try #require(try sets(in: decoded).first?.intensity)
        #expect(intensity.scale.rawValue == "watts")
        #expect(intensity.value == "300")
    }

    // MARK: - Refusal

    private func planStating(_ setJSON: String) -> String {
        """
        {
          "version": 6, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "sessions": [{
            "blockOrdinal": 1, "ordinal": 1,
            "entries": [{
              "exerciseID": "barbell-back-squat", "displayName": "Squat",
              "sets": [\(setJSON)]
            }]
          }]
        }
        """
    }

    @Test("An unknown key inside a set is refused, naming the key and where it sat")
    func anUnknownKeyInsideASetIsRefused() throws {
        let error = #expect(throws: DocumentRefusal.self) {
            try decoded(planStating(#"{"clusterRest": 20}"#))
        }
        let message = try #require(error?.errorDescription)
        #expect(message.contains("clusterRest"))
        #expect(message.contains("sessions → 0 → entries → 0 → sets → 0"))
    }

    @Test("An unknown key inside an intensity target is refused too")
    func anUnknownKeyInsideIntensityIsRefused() throws {
        let error = #expect(throws: DocumentRefusal.self) {
            try decoded(planStating(#"{"intensity": {"scale": "rpe", "value": "8", "of": "3RM"}}"#))
        }
        #expect(try #require(error?.errorDescription).contains("of"))
    }

    @Test("An intensity that does not say what scale it is on is refused, not guessed")
    func anIntensityWithoutAScaleIsRefused() throws {
        // A bare 8 is an RPE, an RIR or a percentage depending on who wrote it,
        // and picking one would be the app deciding how hard to train.
        #expect(throws: (any Error).self) {
            try decoded(planStating(#"{"intensity": {"value": "8"}}"#))
        }
    }

    @Test("A target this build cannot read is refused rather than stored as text")
    func anUnreadableTargetIsRefused() {
        #expect(throws: (any Error).self) {
            try decoded(planStating(#"{"target": "heavy"}"#))
        }
    }
}
