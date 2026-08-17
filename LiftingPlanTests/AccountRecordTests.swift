import Testing
import Foundation
import SwiftData
@testable import LiftingPlan
import LiftingKit

/// What the account page says about a lifter, and what it says about a lifter
/// nobody has described yet.
///
/// The second half is the one worth guarding. The app asks the lifter nothing,
/// so an empty record is the normal first state and stays partly empty for a
/// long time — every rule about how absence reads is a rule about the common
/// case, not an edge case. These are string comparisons because that is what
/// the screen prints; asserting them through a `List` would need a simulator to
/// check what a `String` already answers.
@Suite("The account record")
struct AccountRecordTests {

    private static let catalog: ExerciseCatalog = {
        // The real bundled catalog: resolving a slug to the name a lifter reads
        // is the thing under test, and a fixture would prove only that a
        // fixture resolves.
        (try? ExerciseCatalog.bundled()) ?? ExerciseCatalog(exercises: [], version: 0)
    }()

    private static let bench = ExerciseID(rawValue: "barbell-bench-press")
    private static let squat = ExerciseID(rawValue: "barbell-squat")

    /// 2026-08-12.
    private static let weighInDay = Date(timeIntervalSince1970: 1_786_000_000)

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    private func emptyProfile() throws -> UserProfile {
        let profile = UserProfile()
        let context = try context()
        context.insert(profile)
        return profile
    }

    private func facts(
        _ profile: UserProfile, weighIns: [BodyMetric] = []
    ) -> [LifterFactRow] {
        AccountRecord.facts(profile: profile, weighIns: weighIns, catalog: Self.catalog)
    }

    // MARK: - The day-one lifter

    @Test("A lifter nobody has described has no facts to show")
    func nothingStated() throws {
        #expect(facts(try emptyProfile()).isEmpty)
    }

    @Test("Everything the record can hold is named as not yet said")
    func everythingIsUnstated() throws {
        let unstated = AccountRecord.notYetSaid(
            profile: try emptyProfile(), weighIns: [], baselineCount: 0)
        #expect(unstated == [
            "goal", "experience", "constraints", "bodyweight",
            "equipment", "training days", "session length", "strength baselines",
        ])
    }

    @Test("The eight names read as one sentence rather than eight blank rows")
    func unstatedReadsAsASentence() throws {
        let sentence = AccountRecord.sentence(["goal", "bodyweight", "equipment"])
        #expect(sentence == "Goal, bodyweight and equipment.")
        #expect(AccountRecord.sentence(["goal"]) == "Goal.")
        #expect(AccountRecord.sentence(["goal", "bodyweight"]) == "Goal and bodyweight.")
        #expect(AccountRecord.sentence([]) == nil)
    }

    // MARK: - A record with something in it

    @Test("Every fact stated is a row, in reading order")
    func statedFactsInOrder() throws {
        let profile = try emptyProfile()
        profile.goal = "Add 20 lb to my squat"
        profile.experience = .intermediate
        profile.constraints = "Left shoulder hurts overhead"
        profile.bodyweight = Mass(value: 185, unit: .pounds)
        profile.ownedEquipment = [.barbell, .band]
        profile.preferredWeekdays = [.monday, .wednesday, .friday]
        profile.preferredDurationMinutes = 60

        let rows = facts(profile)
        #expect(rows.map(\.label) == [
            "Goal", "Experience", "Constraints", "Bodyweight",
            "Equipment", "Training days", "Session length",
        ])
        #expect(rows.map(\.value) == [
            "Add 20 lb to my squat", "Intermediate", "Left shoulder hurts overhead",
            "185 lb", "Band, Barbell", "Mon, Wed, Fri", "60 min",
        ])
    }

    @Test("A stated fact is never also reported as not yet said")
    func statedAndUnstatedDoNotOverlap() throws {
        let profile = try emptyProfile()
        profile.goal = "Get stronger"
        profile.preferredDurationMinutes = 45

        let unstated = AccountRecord.notYetSaid(profile: profile, weighIns: [], baselineCount: 0)
        #expect(!unstated.contains("goal"))
        #expect(!unstated.contains("session length"))
        #expect(unstated.count == 6)
    }

    @Test("A lifter who owns nothing is not a lifter nobody asked")
    func ownsNothingIsAStatement() throws {
        let profile = try emptyProfile()
        profile.ownedEquipment = []

        #expect(facts(profile).first?.value == "No equipment")
        #expect(!AccountRecord.notYetSaid(profile: profile, weighIns: [], baselineCount: 0)
            .contains("equipment"))
    }

    @Test("A weight is shown in the unit it was stated in, never converted")
    func weightKeepsItsUnit() throws {
        let profile = try emptyProfile()
        profile.displayUnit = .pounds
        profile.bodyweight = Mass(value: 84, unit: .kilograms)

        #expect(facts(profile).first?.value == "84 kg")
    }

    // MARK: - Bodyweight is a series

    @Test("Bodyweight shows the latest reading and when it was taken")
    func bodyweightShowsTheLatestReading() throws {
        let profile = try emptyProfile()
        let older = BodyMetric(
            date: Self.weighInDay.addingTimeInterval(-86_400 * 7),
            bodyweight: Mass(value: 190, unit: .pounds))
        let latest = BodyMetric(
            date: Self.weighInDay, bodyweight: Mass(value: 185, unit: .pounds))

        let row = try #require(facts(profile, weighIns: [older, latest]).first)
        #expect(row.value == "185 lb")
        #expect(row.label
            == "Bodyweight · \(Self.weighInDay.formatted(date: .abbreviated, time: .omitted))")
    }

    @Test("A reading with no weight in it does not become the latest")
    func emptyReadingIsNotAReading() throws {
        let profile = try emptyProfile()
        let real = BodyMetric(
            date: Self.weighInDay, bodyweight: Mass(value: 185, unit: .pounds))
        let empty = BodyMetric(date: Self.weighInDay.addingTimeInterval(86_400), bodyweight: nil)

        #expect(facts(profile, weighIns: [real, empty]).first?.value == "185 lb")
    }

    @Test("A weight with no reading behind it says no date it cannot support")
    func bodyweightWithoutASeries() throws {
        let profile = try emptyProfile()
        profile.bodyweight = Mass(value: 185, unit: .pounds)

        #expect(facts(profile).first?.label == "Bodyweight")
    }

    // MARK: - Baselines

    @Test("A baseline names the exercise the lifter would name, not its slug")
    func baselineResolvesItsExercise() {
        let rows = AccountRecord.baselines(
            [StrengthBaseline(
                exerciseID: Self.bench, load: Mass(value: 205, unit: .pounds), reps: 5)],
            catalog: Self.catalog)

        #expect(rows.map(\.label) == ["Barbell Bench Press"])
        #expect(rows.map(\.value) == ["205 lb × 5"])
    }

    @Test("Baselines are listed by the name they are read under")
    func baselinesAreOrderedByName() {
        let rows = AccountRecord.baselines(
            [
                StrengthBaseline(
                    exerciseID: Self.squat, load: Mass(value: 275, unit: .pounds), reps: 3),
                StrengthBaseline(
                    exerciseID: Self.bench, load: Mass(value: 205, unit: .pounds), reps: 5),
            ],
            catalog: Self.catalog)

        #expect(rows.map(\.label) == ["Barbell Bench Press", "Barbell Squat"])
    }

    @Test("A bodyweight baseline states no load rather than a zero")
    func bodyweightBaseline() {
        let rows = AccountRecord.baselines(
            [StrengthBaseline(
                exerciseID: ExerciseID(rawValue: "bodyweight-squat"), load: nil, reps: 20)],
            catalog: Self.catalog)

        #expect(rows.map(\.value) == ["Bodyweight × 20"])
    }

    @Test("An exercise this build's catalog has never heard of keeps its own id")
    func unknownExerciseKeepsItsID() {
        // The inbox refuses a baseline the catalog does not have, so this only
        // arrives from a record synced from a build with newer data. Showing
        // the id is honest; inventing a name for it would not be.
        let rows = AccountRecord.baselines(
            [StrengthBaseline(exerciseID: ExerciseID(rawValue: "sled-hip-thrust"), reps: 8)],
            catalog: Self.catalog)

        #expect(rows.map(\.label) == ["sled-hip-thrust"])
    }

    @Test("Baselines are not reported as unsaid once there is one")
    func baselinesCloseTheirOwnFact() throws {
        let unstated = AccountRecord.notYetSaid(
            profile: try emptyProfile(), weighIns: [], baselineCount: 1)
        #expect(!unstated.contains("strength baselines"))
    }

    // MARK: - What he avoids

    @Test("What he avoids is shown when there is something, and never counted as unsaid")
    func avoidances() throws {
        let profile = try emptyProfile()
        profile.avoidedPatterns = [.verticalPress]
        profile.avoidedExercises = [Self.bench]

        let rows = facts(profile)
        #expect(rows.map(\.label) == ["Avoided movements", "Avoided exercises"])
        #expect(rows.map(\.value) == ["Vertical press", "Barbell Bench Press"])
        // Empty lists cannot be told from a lifter who avoids nothing, so
        // "not yet said" would be an assertion the record cannot support.
        let unstated = AccountRecord.notYetSaid(profile: profile, weighIns: [], baselineCount: 0)
        #expect(!unstated.contains { $0.contains("avoid") })
    }

    @Test("Nothing avoided draws no row at all")
    func noAvoidancesNoRows() throws {
        #expect(facts(try emptyProfile()).isEmpty)
    }
}
