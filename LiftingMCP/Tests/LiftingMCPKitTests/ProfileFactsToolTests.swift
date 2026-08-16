import Foundation
import Testing
import LiftingKit

@testable import LiftingMCPKit

/// The two facts `update_profile` used to drop on the floor — what the lifter
/// weighs and what he could already do — and the gym it could not describe.
///
/// The failure these guard was silent: `bodyweight` was accepted, reported as
/// "Recorded", and written down nowhere, so Claude was permanently told the
/// lifter had no bodyweight and no strength anchor to plan a first block from.
@Suite("update_profile: bodyweight, baselines, equipment")
struct ProfileFactsToolTests {

    private func update(_ arguments: JSONValue) throws -> (ToolOutcome, InMemoryDocuments) {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot())
        let outcome = try makeRunner(documents: documents)
            .call(ToolCatalog.updateProfile, arguments: arguments)
        return (outcome, documents)
    }

    // MARK: - Bodyweight

    @Test("A bodyweight is recorded rather than silently dropped")
    func bodyweightIsRecorded() throws {
        let (outcome, documents) = try update([
            "bodyweight": ["value": 182.5, "unit": "lb"]
        ])
        let written = try #require(documents.lastWrittenProfileUpdate)

        #expect(written.bodyweight.count == 1)
        #expect(written.bodyweight.first?.mass == Mass(value: 182.5, unit: .pounds))
        #expect(outcome.report?["recorded"]?["bodyweight"]?["state"]?.stringValue == "recorded")
    }

    @Test("A reading that names no day belongs to the day the update was written")
    func undatedReadingIsDatedByTheDocument() throws {
        let (_, documents) = try update(["bodyweight": ["value": 82, "unit": "kg"]])
        let written = try #require(documents.lastWrittenProfileUpdate)

        #expect(written.bodyweight.first?.resolvedDate(from: written.generatedAt) == referenceNow)
    }

    @Test("Two readings on different days are recorded as a series, not as one number")
    func twoReadingsAreASeries() throws {
        let (_, documents) = try update([
            "bodyweight": [
                ["date": "2026-08-01T12:00:00Z", "value": 180, "unit": "lb"],
                ["date": "2026-08-08T12:00:00Z", "value": 182, "unit": "lb"],
            ]
        ])
        let written = try #require(documents.lastWrittenProfileUpdate)

        #expect(written.bodyweight.count == 2)
        #expect(written.bodyweight.map(\.mass.value) == [180, 182])
    }

    @Test("A weight with no unit is refused rather than guessed at")
    func unitlessWeightIsRefused() throws {
        let (outcome, documents) = try update(["bodyweight": 182])

        #expect(documents.lastWrittenProfileUpdate == nil)
        #expect(try #require(outcome.failureMessage).contains("unit"))
    }

    @Test("A unit written as a word is understood, as it is everywhere else here")
    func unitIsReadLoosely() throws {
        let (_, documents) = try update(["bodyweight": ["value": 82, "unit": "kilograms"]])

        #expect(documents.lastWrittenProfileUpdate?.bodyweight.first?.mass.unit == .kilograms)
    }

    // MARK: - Baselines

    @Test("A strength baseline is recorded against the lift it is about")
    func baselineIsRecorded() throws {
        let (outcome, documents) = try update([
            "baselines": [
                [
                    "exerciseID": "barbell-bench-press",
                    "load": ["value": 205, "unit": "lb"], "reps": 5,
                ]
            ]
        ])
        let written = try #require(documents.lastWrittenProfileUpdate)

        #expect(written.baselines.count == 1)
        #expect(
            written.baselines.first?.exerciseID == ExerciseID(rawValue: "barbell-bench-press"))
        #expect(written.baselines.first?.load == Mass(value: 205, unit: .pounds))
        #expect(written.baselines.first?.reps == 5)
        #expect(outcome.report?["recorded"]?["baselines"]?["state"]?.stringValue == "recorded")
    }

    @Test("A baseline with no load is bodyweight work, not zero pounds")
    func loadlessBaselineIsBodyweight() throws {
        let (_, documents) = try update([
            "baselines": ["exerciseID": "push-up", "reps": 20]
        ])

        #expect(documents.lastWrittenProfileUpdate?.baselines.first?.load == nil)
        #expect(documents.lastWrittenProfileUpdate?.baselines.first?.reps == 20)
    }

    @Test("A baseline naming an exercise the catalog does not have is refused by name")
    func unknownBaselineExerciseIsRefused() throws {
        // History is keyed on exercise identity, so an invented ID would anchor
        // a series nothing else will ever join — the rule PlanImporter applies.
        let (outcome, documents) = try update([
            "baselines": ["exerciseID": "moon-press", "reps": 5]
        ])
        let message = try #require(outcome.failureMessage)

        #expect(message.contains("moon-press"))
        #expect(message.contains(ToolCatalog.listExercises))
        #expect(documents.lastWrittenProfileUpdate == nil, "a refused update must write nothing")
    }

    @Test("A baseline that cannot say how many reps is refused rather than assumed to be one")
    func repslessBaselineIsRefused() throws {
        let (outcome, documents) = try update([
            "baselines": ["exerciseID": "barbell-squat", "load": ["value": 315, "unit": "lb"]]
        ])

        #expect(documents.lastWrittenProfileUpdate == nil)
        #expect(try #require(outcome.failureMessage).contains("reps"))
    }

    @Test("A baseline and a bodyweight in one call are both written")
    func bothFactsInOneCall() throws {
        let (_, documents) = try update([
            "bodyweight": ["value": 182, "unit": "lb"],
            "baselines": ["exerciseID": "barbell-squat", "reps": 5],
        ])
        let written = try #require(documents.lastWrittenProfileUpdate)

        #expect(written.bodyweight.count == 1)
        #expect(written.baselines.count == 1)
    }

    // MARK: - The gym he actually has

    @Test("Barbell and bands but no rack is expressible")
    func garageGymIsExpressible() throws {
        let (_, documents) = try update(["equipment": ["barbell", "band", "plate"]])
        let owned = try #require(documents.lastWrittenProfileUpdate?.equipment.stated)

        #expect(Set(owned) == [.barbell, .band, .plate])
    }

    @Test("A tier and a concrete type can be named together, and both are kept")
    func tierAndTypeMix() throws {
        let (_, documents) = try update(["equipment": ["dumbbells only", "pool"]])
        let owned = try #require(documents.lastWrittenProfileUpdate?.equipment.stated)

        #expect(Set(owned).isSuperset(of: EquipmentAccess.permitted(for: .dumbbellsOnly)))
        #expect(owned.contains(.pool))
    }

    @Test("A lifter who owns nothing at all is recordable, and is not a lifter nobody asked")
    func ownsNothing() throws {
        let (_, documents) = try update(["equipment": []])

        #expect(documents.lastWrittenProfileUpdate?.equipment == .stated([]))
    }

    @Test("The report says what was recorded, so the caller sees the expansion it will get")
    func reportStatesTheOwnedSet() throws {
        let report = try #require(try update(["equipment": "bodyweight only"]).0.report)

        #expect(report["recorded"]?["equipment"]?["state"]?.stringValue == "recorded")
        #expect(report["recorded"]?["equipment"]?["value"] == ["bodyweight"])
    }
}

/// What `list_exercises` does with an owned set, which is the whole reason the
/// tiers had to go: the audit measured a forced `.fullGym` granting 109 machine
/// and cable movements this lifter cannot do.
@Suite("list_exercises: owned equipment")
struct OwnedEquipmentFilterTests {

    private func ids(_ profile: SnapshotProfile?) throws -> [String] {
        let outcome = try makeRunner(documents: InMemoryDocuments(
            snapshot: fixtureSnapshot(profile: profile)
        )).call(ToolCatalog.listExercises, arguments: [:])
        let report = try #require(outcome.report)
        return try #require(report["exercises"]?.arrayValue)
            .compactMap { $0["id"]?.stringValue }
    }

    @Test("A garage gym gets its barbell work and none of the cable work")
    func barbellYesCableNo() throws {
        let owned = EquipmentAccess.permitted(owning: [.barbell, .band])
            .sorted { $0.rawValue < $1.rawValue }

        let found = try ids(fixtureProfile(availableEquipment: owned))

        #expect(found.contains("barbell-bench-press"))
        #expect(found.contains("barbell-squat"))
        #expect(found.contains("push-up"), "a push-up needs none of his equipment")
        #expect(!found.contains("lat-pulldown"), "he has no cable stack")
        #expect(!found.contains("dumbbell-bench-press"), "he owns no dumbbells")
    }

    @Test("A lifter who has stated nothing is unknown — not a full gym, and not nothing at all")
    func statedNothingIsUnknown() throws {
        let found = try ids(fixtureProfile(availableEquipment: nil))

        #expect(found.count == 8, "unknown must not narrow to nothing")
        #expect(found.contains("lat-pulldown"))
    }
}
