import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// What a grouped plan becomes in the store, and what the store says when it is
/// read back.
///
/// Two optional columns carry a group — its identity and a position in the round
/// — and the rest lands on the movement the round ends with, which is where the
/// rest is taken. Nothing here decides that anything is a group: every grouping
/// in these tests was written by the plan.
@Suite("A superset in the store")
struct SupersetStoreTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let bench = ExerciseID(rawValue: "barbell-bench-press")
    private static let fly = ExerciseID(rawValue: "dumbbell-chest-fly")
    private static let pushdown = ExerciseID(rawValue: "cable-rope-pushdown")
    private static let curl = ExerciseID(rawValue: "barbell-curl")

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    private func exercise(
        _ id: ExerciseID, sets: Int = 3, repRange: String = "12-15", restSeconds: Int? = nil
    ) -> PlanDocumentExercise {
        PlanDocumentExercise(
            exerciseID: id, displayName: id.rawValue, sets: sets,
            repRange: repRange, restSeconds: restSeconds
        )
    }

    /// One ungrouped press, then a superset of fly and pushdown resting 90s.
    private func mixedDocument() -> PlanDocument {
        PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            days: [PlanDocumentDay(weekday: .monday, focus: "Push", entries: [
                .exercise(exercise(Self.bench, sets: 4, repRange: "6-8", restSeconds: 180)),
                .group(PlanDocumentGroup(
                    exercises: [exercise(Self.fly), exercise(Self.pushdown)], restSeconds: 90)),
            ])]
        )
    }

    private func day(of plan: TrainingPlan) throws -> WorkoutDay {
        let week = try #require(plan.orderedWeeks.first)
        return try #require(week.orderedDays.first)
    }

    private func imported(_ document: PlanDocument) throws -> WorkoutDay {
        let plan = try PlanImporter.import(
            document, into: try context(), catalog: try ExerciseCatalog.bundled(),
            importedAt: Self.instant)
        return try day(of: plan)
    }

    // MARK: - What the import writes

    @Test("A group's members share one identity and take their position in the round")
    func groupMembersShareAnIdentity() throws {
        let exercises = try imported(mixedDocument()).orderedExercises

        #expect(exercises.map(\.exerciseID) == [Self.bench, Self.fly, Self.pushdown])
        #expect(exercises[0].groupID == nil, "an ungrouped exercise is in no group")
        #expect(exercises[0].groupPosition == nil)
        let identity = try #require(exercises[1].groupID)
        #expect(exercises[2].groupID == identity)
        #expect(exercises[1].groupPosition == 0)
        #expect(exercises[2].groupPosition == 1)
    }

    @Test("The group's rest lands where the rest is taken: after the round")
    func groupRestLandsOnTheLastMember() throws {
        let exercises = try imported(mixedDocument()).orderedExercises

        #expect(exercises[1].restSeconds == nil, "nothing is rested between A1 and A2")
        #expect(exercises[2].restSeconds == 90)
    }

    @Test("An ungrouped exercise keeps its own rest and gains nothing")
    func ungroupedExerciseIsUnchanged() throws {
        let exercises = try imported(mixedDocument()).orderedExercises

        #expect(exercises[0].restSeconds == 180)
        #expect(exercises[0].targetSets == 4)
        #expect(exercises[0].repRange == "6-8")
        #expect(exercises[0].order == 0)
    }

    @Test("Two groups in one day are two identities, not one")
    func twoGroupsAreTwoIdentities() throws {
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            days: [PlanDocumentDay(weekday: .monday, entries: [
                .group(PlanDocumentGroup(
                    exercises: [exercise(Self.fly), exercise(Self.pushdown)], restSeconds: 90)),
                .group(PlanDocumentGroup(
                    exercises: [exercise(Self.curl), exercise(Self.bench)], restSeconds: 60)),
            ])]
        )
        let exercises = try imported(document).orderedExercises

        #expect(exercises[0].groupID == exercises[1].groupID)
        #expect(exercises[2].groupID == exercises[3].groupID)
        #expect(exercises[0].groupID != exercises[2].groupID)
        #expect(exercises.map(\.order) == [0, 1, 2, 3])
    }

    @Test("A per-set prescription inside a group still reaches every set of it")
    func perSetPrescriptionSurvivesGrouping() throws {
        let ramp = PlanDocumentExercise(
            exerciseID: Self.fly, displayName: "Fly",
            sets: [
                SetPrescription(suggestedLoad: Mass(value: 20, unit: .pounds)),
                SetPrescription(suggestedLoad: Mass(value: 25, unit: .pounds)),
                SetPrescription(repRange: "8", notes: "last one to failure"),
            ],
            repRange: "12"
        )
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            days: [PlanDocumentDay(weekday: .monday, entries: [
                .group(PlanDocumentGroup(
                    exercises: [ramp, exercise(Self.pushdown)], restSeconds: 90))
            ])]
        )
        let member = try #require(try imported(document).orderedExercises.first)

        #expect(member.prescribedSets.map(\.repRange) == ["12", "12", "8"])
        #expect(member.prescribedSets.map { $0.suggestedLoad?.value } == [20, 25, nil])
        #expect(member.prescribedSets.last?.notes == "last one to failure")
    }

    // MARK: - What the store says when it is read back

    @Test("A day of ungrouped exercises reads back as exercises, one entry each")
    func ungroupedDayReadsBackFlat() throws {
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            days: [PlanDocumentDay(weekday: .monday, exercises: [
                exercise(Self.bench), exercise(Self.curl),
            ])]
        )
        let entries = try imported(document).entries

        #expect(entries.count == 2)
        #expect(entries.allSatisfy { if case .exercise = $0 { true } else { false } })
    }

    @Test("A group reads back as one entry, its members in round order")
    func groupReadsBackAsOneEntry() throws {
        let entries = try imported(mixedDocument()).entries

        #expect(entries.count == 2)
        guard case .group(let group) = entries[1] else {
            Issue.record("the second entry is the group")
            return
        }
        #expect(group.members.map(\.exerciseID) == [Self.fly, Self.pushdown])
        #expect(group.restSeconds == 90)
        #expect(group.prescribedRounds == 3)
        #expect(group.title == "Superset A")
        #expect(group.notation(for: group.members[0]) == "A1")
        #expect(group.notation(for: group.members[1]) == "A2")
    }

    @Test("The first group of a day is A and the next is B")
    func groupsAreLetteredInOrder() throws {
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            days: [PlanDocumentDay(weekday: .monday, entries: [
                .exercise(exercise(Self.bench, restSeconds: 180)),
                .group(PlanDocumentGroup(
                    exercises: [exercise(Self.fly), exercise(Self.pushdown)], restSeconds: 90)),
                .group(PlanDocumentGroup(
                    exercises: [exercise(Self.curl), exercise(Self.bench)], restSeconds: 60)),
            ])]
        )
        let letters = try imported(document).entries.compactMap { entry -> String? in
            guard case .group(let group) = entry else { return nil }
            return group.letter
        }
        #expect(letters == ["A", "B"])
    }

    @Test("A group of three is a tri-set and one of four a giant set")
    func groupsAreNamedBySize() throws {
        func title(ofGroupOf size: Int) throws -> String {
            let members = [Self.fly, Self.pushdown, Self.curl, Self.bench].prefix(size)
            let document = PlanDocument(
                id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
                days: [PlanDocumentDay(weekday: .monday, entries: [
                    .group(PlanDocumentGroup(
                        exercises: members.map { exercise($0) }, restSeconds: 90))
                ])]
            )
            guard case .group(let group)? = try imported(document).entries.first else {
                Issue.record("a group was prescribed")
                return ""
            }
            return group.title
        }

        #expect(try title(ofGroupOf: 2) == "Superset A")
        #expect(try title(ofGroupOf: 3) == "Tri-set A")
        #expect(try title(ofGroupOf: 4) == "Giant set A")
    }

    @Test("A group that arrives with one member left reads as the exercise it is")
    func halfSyncedGroupDegradesToAnExercise() throws {
        // Not something the format can state — this is a record that arrived
        // incomplete, which CloudKit can produce and a screen must survive.
        let context = try context()
        let day = WorkoutDay(weekday: .monday)
        let stranded = PlannedExercise(
            exerciseID: Self.fly, displayName: "Fly", order: 0, targetSets: 3)
        stranded.groupID = UUID()
        stranded.groupPosition = 0
        day.exercises = [stranded]
        context.insert(day)

        let entries = day.entries
        #expect(entries.count == 1)
        #expect(entries.allSatisfy { if case .exercise = $0 { true } else { false } })
    }

    @Test("Grouping is read from what the plan said, never from what sits beside what")
    func nothingIsGroupedByProximity() throws {
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            days: [PlanDocumentDay(weekday: .monday, exercises: [
                exercise(Self.fly), exercise(Self.pushdown), exercise(Self.curl),
            ])]
        )
        let entries = try imported(document).entries

        #expect(entries.count == 3, "three exercises in a row are three exercises")
        #expect(try imported(document).orderedExercises.allSatisfy { $0.groupID == nil })
    }
}
