import Foundation
import Testing
@testable import LiftingKit

/// What the snapshot says on the wire about an exercise performed in a group.
///
/// A superset reported as unrelated sets loses the one thing it was: work done
/// in rounds. These pin the key that says so, and pin that an exercise performed
/// on its own says nothing extra at all.
@Suite("A grouped exercise on the snapshot wire")
struct SnapshotGroupWireTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let groupID = UUID(uuidString: "3E7F7E2E-2B47-4C51-9E58-52C1D1F0A0B1")

    private func exercise(
        _ id: String, order: Int, restSeconds: Int?, group: SnapshotExerciseGroup?
    ) -> SnapshotPlannedExercise {
        SnapshotPlannedExercise(
            exerciseID: ExerciseID(rawValue: id), displayName: id, order: order,
            targetSets: 3, repRange: "12-15", suggestedLoad: nil, restSeconds: restSeconds,
            tempo: nil, notes: nil, loggedSets: [], group: group
        )
    }

    private func encoded(_ exercise: SnapshotPlannedExercise) throws -> String {
        let data = try TrainingSnapshot.makeEncoder().encode(exercise)
        return try #require(String(data: data, encoding: .utf8))
    }

    @Test("A grouped exercise says which group it was performed in and where")
    func groupedExerciseCarriesItsGroup() throws {
        let id = try #require(Self.groupID)
        let member = exercise(
            "dumbbell-chest-fly", order: 1, restSeconds: nil,
            group: SnapshotExerciseGroup(
                id: id, letter: "A", position: 1, size: 2, restSeconds: 90))
        let text = try encoded(member)

        #expect(text.contains("\"group\""))
        #expect(text.contains("\"letter\" : \"A\""))
        #expect(text.contains("\"position\" : 1"))
        #expect(text.contains("\"size\" : 2"))
        #expect(member.group?.notation == "A1")
        #expect(member.group?.restSeconds == 90)
    }

    @Test("An exercise performed on its own writes no group at all")
    func ungroupedExerciseSaysNothingExtra() throws {
        let text = try encoded(
            exercise("barbell-bench-press", order: 0, restSeconds: 180, group: nil))

        #expect(!text.contains("\"group\""))
        #expect(text.contains("\"restSeconds\" : 180"))
    }

    @Test("A snapshot written before groups existed reads as ungrouped rather than failing")
    func earlierSnapshotDecodes() throws {
        let json = """
        {"exerciseID": "barbell-bench-press", "displayName": "Bench", "order": 0,
         "targetSets": 3, "repRange": "5", "loggedSets": []}
        """
        let decoded = try TrainingSnapshot.makeDecoder()
            .decode(SnapshotPlannedExercise.self, from: Data(json.utf8))

        #expect(decoded.group == nil)
        #expect(decoded.targetSets == 3)
    }

    @Test("A group survives a round trip whole")
    func groupRoundTrips() throws {
        let id = try #require(Self.groupID)
        let original = exercise(
            "cable-rope-pushdown", order: 2, restSeconds: 90,
            group: SnapshotExerciseGroup(
                id: id, letter: "B", position: 3, size: 3, restSeconds: 90))
        let data = try TrainingSnapshot.makeEncoder().encode(original)
        let decoded = try TrainingSnapshot.makeDecoder()
            .decode(SnapshotPlannedExercise.self, from: data)

        #expect(decoded == original)
        #expect(decoded.group?.notation == "B3")
    }
}
