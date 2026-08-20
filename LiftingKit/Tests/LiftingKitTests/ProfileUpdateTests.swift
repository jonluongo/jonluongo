import Foundation
import Testing

@testable import LiftingKit

/// The three-way patch document, which is the only way facts about the lifter
/// reach the app now that it asks him nothing.
///
/// The assertions that matter are about telling *absent* from *null*: an update
/// that could not tell them apart would either wipe the profile on every partial
/// change or make a fact recorded in error impossible to take back.
@Suite("Profile update")
struct ProfileUpdateTests {

    /// A fixed instant on a second boundary, so ISO 8601 round-trips it exactly.
    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let identity = UUID(uuidString: "11111111-2222-3333-4444-555555555555")

    private func update(
        experience: StatedValue<ExperienceLevel> = .unchanged,
        equipment: StatedValue<[EquipmentType]> = .unchanged,
        goal: StatedValue<String> = .unchanged,
        preferredDurationMinutes: StatedValue<Int> = .unchanged
    ) throws -> ProfileUpdate {
        ProfileUpdate(
            id: try #require(Self.identity), generatedAt: Self.instant,
            experience: experience, equipment: equipment, goal: goal,
            preferredDurationMinutes: preferredDurationMinutes
        )
    }

    private func roundTrip(_ update: ProfileUpdate) throws -> ProfileUpdate {
        let data = try ProfileUpdate.makeEncoder().encode(update)
        return try ProfileUpdate.makeDecoder().decode(ProfileUpdate.self, from: data)
    }

    private func encodedJSON(_ update: ProfileUpdate) throws -> String {
        String(decoding: try ProfileUpdate.makeEncoder().encode(update), as: UTF8.self)
    }

    // MARK: - The three states survive the trip

    @Test("An update carrying all three states round-trips with each one intact")
    func allThreeStatesRoundTrip() throws {
        let original = try update(
            experience: .stated(.advanced), equipment: .unstated,
            goal: .stated("Bigger bench")
        )

        let decoded = try roundTrip(original)

        #expect(decoded == original)
        #expect(decoded.experience == .stated(.advanced))
        #expect(decoded.equipment == .unstated)
        #expect(decoded.preferredDurationMinutes == .unchanged)
    }

    @Test("A field the update says nothing about writes no key at all")
    func unchangedFieldWritesNoKey() throws {
        let json = try encodedJSON(try update(goal: .stated("Bigger bench")))

        #expect(json.contains("\"goal\""))
        #expect(!json.contains("\"experience\""))
        #expect(!json.contains("\"equipment\""))
    }

    @Test("A field the update takes back writes an explicit null, not an absent key")
    func unstatedFieldWritesNull() throws {
        let json = try encodedJSON(try update(equipment: .unstated))

        #expect(json.contains("\"equipment\" : null"))
    }

    @Test("An absent key and an explicit null decode differently")
    func absentAndNullAreDifferent() throws {
        let json = """
            {"version": 2, "id": "11111111-2222-3333-4444-555555555555",
             "generatedAt": "2023-11-14T22:13:20Z", "experience": null}
            """

        let decoded = try ProfileUpdate.makeDecoder()
            .decode(ProfileUpdate.self, from: Data(json.utf8))

        #expect(decoded.experience == .unstated)
        #expect(decoded.equipment == .unchanged)
    }

    @Test("Experience a fixed vocabulary could not hold is recorded rather than refused")
    func describedExperienceIsRecorded() throws {
        let json = """
            {"version": 3, "id": "11111111-2222-3333-4444-555555555555",
             "generatedAt": "2023-11-14T22:13:20Z",
             "experience": "returning after two years off"}
            """

        let decoded = try ProfileUpdate.makeDecoder()
            .decode(ProfileUpdate.self, from: Data(json.utf8))

        #expect(decoded.experience == .stated(ExperienceLevel(rawValue: "returning after two years off")))
        #expect(try encodedJSON(roundTrip(decoded)).contains("returning after two years off"))
    }

    @Test("A version 2 update's capitalized experience still reads as the same level")
    func legacyExperienceCasingStillReads() throws {
        let json = """
            {"version": 2, "id": "11111111-2222-3333-4444-555555555555",
             "generatedAt": "2023-11-14T22:13:20Z", "experience": "Intermediate"}
            """

        let decoded = try ProfileUpdate.makeDecoder()
            .decode(ProfileUpdate.self, from: Data(json.utf8))

        #expect(decoded.experience == .stated(.intermediate))
    }

    @Test("An update that names no fact at all says so rather than pretending to change one")
    func emptyUpdateStatesNothing() throws {
        #expect(try update().statesNothing)
        #expect(!(try update(goal: .stated("")).statesNothing))
        // Taking a fact back is a change, not an absence of one.
        #expect(!(try update(equipment: .unstated).statesNothing))
    }

    @Test("An update that cannot say what or when it is fails to decode")
    func identityAndTimestampAreRequired() {
        let json = #"{"version": 2, "goal": "Bigger bench"}"#

        #expect(throws: (any Error).self) {
            try ProfileUpdate.makeDecoder().decode(ProfileUpdate.self, from: Data(json.utf8))
        }
    }

    // MARK: - Resolving against what is stored

    @Test("An unchanged field leaves what is stored exactly as it was")
    func unchangedResolvesToStored() {
        #expect(StatedValue<Int>.unchanged.resolved(from: 45) == 45)
        #expect(StatedValue<Int>.unchanged.resolved(from: nil) == nil)
    }

    @Test("A stated field replaces what is stored, including when nothing was stored")
    func statedResolvesToTheNewValue() {
        #expect(StatedValue.stated(60).resolved(from: 45) == 60)
        #expect(StatedValue.stated(60).resolved(from: nil) == 60)
    }

    @Test("An unstated field returns the fact to not-known rather than to a default")
    func unstatedResolvesToNothing() {
        #expect(StatedValue<Int>.unstated.resolved(from: 45) == nil)
        #expect(StatedValue<[EquipmentType]>.unstated.resolved(from: [.barbell]) == nil)
    }

    // MARK: - Unknown values still round-trip

    @Test("A movement pattern this build does not know survives an update intact")
    func unknownAvoidedPatternSurvives() throws {
        let unknown = MovementPattern(rawValue: "anti-rotation")
        #expect(!unknown.isKnown)

        let original = ProfileUpdate(
            id: try #require(Self.identity), generatedAt: Self.instant,
            avoidedPatterns: .stated([unknown, .hinge])
        )

        #expect(try roundTrip(original).avoidedPatterns == .stated([unknown, .hinge]))
    }

    @Test("Equipment this build has never heard of round-trips rather than rejecting the update")
    func unknownEquipmentSurvives() throws {
        // Refusing the document here would refuse a true fact about the lifter
        // at the exact moment someone is trying to record it.
        let unknown = EquipmentType(rawValue: "reverse hyper")
        #expect(!unknown.isKnown)

        let decoded = try roundTrip(try update(equipment: .stated([.barbell, unknown])))

        #expect(decoded.equipment == .stated([.barbell, unknown]))
    }

    @Test("An unrecognized value in the old tier key is carried, not rejected")
    func unknownLegacyTierIsCarried() throws {
        let json = """
            {"version": 1, "id": "11111111-2222-3333-4444-555555555555",
             "generatedAt": "2023-11-14T22:13:20Z", "equipmentAccess": "commercial gym"}
            """

        let decoded = try ProfileUpdate.makeDecoder()
            .decode(ProfileUpdate.self, from: Data(json.utf8))

        #expect(decoded.equipment == .stated([EquipmentType(rawValue: "commercial gym")]))
    }

    // MARK: - Reading a document written before the format widened

    @Test("A version 1 update's tier is read as the equipment it stands for")
    func legacyTierBecomesTheTypesItStandsFor() throws {
        let json = """
            {"version": 1, "id": "11111111-2222-3333-4444-555555555555",
             "generatedAt": "2023-11-14T22:13:20Z", "equipmentAccess": "Dumbbells only"}
            """

        let decoded = try ProfileUpdate.makeDecoder()
            .decode(ProfileUpdate.self, from: Data(json.utf8))
        let owned = try #require(decoded.equipment.stated)

        #expect(Set(owned) == EquipmentAccess.permitted(for: .dumbbellsOnly))
    }

    @Test("A version 1 update that takes the tier back still takes the equipment back")
    func legacyTierNullStillClears() throws {
        let json = """
            {"version": 1, "id": "11111111-2222-3333-4444-555555555555",
             "generatedAt": "2023-11-14T22:13:20Z", "equipmentAccess": null}
            """

        let decoded = try ProfileUpdate.makeDecoder()
            .decode(ProfileUpdate.self, from: Data(json.utf8))

        #expect(decoded.equipment == .unstated)
    }

    @Test("An update stating both the tier and the owned set is refused rather than resolved")
    func bothEquipmentKeysAreRefused() {
        let json = """
            {"version": 2, "id": "11111111-2222-3333-4444-555555555555",
             "generatedAt": "2023-11-14T22:13:20Z",
             "equipmentAccess": "Full gym", "equipment": ["barbell"]}
            """

        #expect(throws: DocumentRefusal.self) {
            try ProfileUpdate.makeDecoder().decode(ProfileUpdate.self, from: Data(json.utf8))
        }
    }

    @Test("An update from a later format is refused whole rather than read in part")
    func laterVersionIsRefused() {
        let json = """
            {"version": 99, "id": "11111111-2222-3333-4444-555555555555",
             "generatedAt": "2023-11-14T22:13:20Z", "goal": "Bigger bench"}
            """

        #expect(throws: DocumentRefusal.self) {
            try ProfileUpdate.makeDecoder().decode(ProfileUpdate.self, from: Data(json.utf8))
        }
    }
}

/// Folding a new update onto one the phone has not taken in yet.
///
/// The shared folder holds one update at a time, and two calls in a single
/// conversation are ordinary — so replacing rather than folding would silently
/// drop everything the first one recorded.
@Suite("Profile update folding")
struct ProfileUpdateFoldingTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)

    private func update(
        experience: StatedValue<ExperienceLevel> = .unchanged,
        goal: StatedValue<String> = .unchanged,
        preferredDurationMinutes: StatedValue<Int> = .unchanged
    ) -> ProfileUpdate {
        ProfileUpdate(
            id: UUID(), generatedAt: Self.instant, experience: experience, goal: goal,
            preferredDurationMinutes: preferredDurationMinutes
        )
    }

    @Test("What the earlier update said and the later one does not is kept")
    func earlierFactsSurvive() {
        let earlier = update(experience: .stated(.advanced))
        let later = update(goal: .stated("Bigger bench"))

        let folded = later.superseding(earlier)

        #expect(folded.experience == .stated(.advanced))
        #expect(folded.goal == .stated("Bigger bench"))
    }

    @Test("Where they disagree the later update wins")
    func laterFactsWin() {
        let folded = update(goal: .stated("Bigger squat"))
            .superseding(update(goal: .stated("Bigger bench")))

        #expect(folded.goal == .stated("Bigger squat"))
    }

    @Test("Taking a fact back is not undone by folding, in either direction")
    func clearingIsPreserved() {
        #expect(
            update(goal: .stated("Bigger bench")).superseding(update(experience: .unstated))
                .experience == .unstated)
        #expect(
            update(experience: .unstated).superseding(update(experience: .stated(.advanced)))
                .experience == .unstated)
    }

    @Test("The folded document keeps the later update's identity, since that is what is written")
    func identityIsTheLaterOne() {
        let later = update(goal: .stated("Bigger bench"))

        let folded = later.superseding(update(experience: .stated(.advanced)))

        #expect(folded.id == later.id)
        #expect(folded.generatedAt == later.generatedAt)
    }

    @Test("Folding onto an update that states nothing changes nothing")
    func foldingOntoAnEmptyUpdateIsANoOp() {
        let later = update(goal: .stated("Bigger bench"), preferredDurationMinutes: .stated(45))

        #expect(later.superseding(update()) == later)
    }

    // MARK: - A baseline has to be at least one repetition

    @Test("A baseline of zero repetitions is refused, not recorded")
    func aBaselineOfNothingIsRefused() {
        // It would be shown to the lifter as "225 lb × 0" on the one page that
        // says what he can already do — a set nobody performed, recorded as a
        // fact about him.
        #expect(throws: DocumentRefusal.self) {
            try ProfileUpdate.makeDecoder().decode(
                ProfileUpdate.self,
                from: Data("""
                    {"version": 3, "id": "11111111-2222-3333-4444-555555555555",
                     "generatedAt": "2023-11-14T22:13:20Z",
                     "baselines": [{"exerciseID": "barbell-bench-press",
                                    "load": {"value": 225, "unit": "lb"}, "reps": 0}]}
                    """.utf8))
        }
    }

    @Test("The refusal names the lift, so the one to fix is obvious")
    func theRefusalNamesTheLift() {
        do {
            _ = try ProfileUpdate.makeDecoder().decode(
                ProfileUpdate.self,
                from: Data("""
                    {"version": 3, "id": "11111111-2222-3333-4444-555555555555",
                     "generatedAt": "2023-11-14T22:13:20Z",
                     "baselines": [{"exerciseID": "barbell-squat", "reps": 0}]}
                    """.utf8))
            Issue.record("a baseline of zero has to be refused")
        } catch {
            #expect("\(error)".contains("barbell-squat") || (error as? DocumentRefusal)
                .map { ($0.errorDescription ?? "").contains("barbell-squat") } == true)
        }
    }

    @Test("A baseline of one repetition is a fact and is kept")
    func oneRepetitionIsEnough() throws {
        let update = try ProfileUpdate.makeDecoder().decode(
            ProfileUpdate.self,
            from: Data("""
                {"version": 3, "id": "11111111-2222-3333-4444-555555555555",
                 "generatedAt": "2023-11-14T22:13:20Z",
                 "baselines": [{"exerciseID": "barbell-squat",
                                "load": {"value": 315, "unit": "lb"}, "reps": 1}]}
                """.utf8))

        #expect(update.baselines.first?.reps == 1)
    }
}
