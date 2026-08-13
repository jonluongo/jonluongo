import Foundation
import SwiftData

/// A prescribed movement within a session, plus the sets actually logged for it.
@Model
final class PlannedExercise {
    var name: String
    var muscleGroup: String
    var order: Int
    var targetSets: Int
    /// Human-readable rep target, e.g. "8-12" or "5".
    var repRange: String
    /// Suggested working weight in the user's unit, if the model/heuristic proposed one.
    /// `nil` means bodyweight or "pick a challenging weight".
    var suggestedWeight: Double?
    /// Rest between sets, in seconds — drives the pace timer.
    var restSeconds: Int
    /// Optional rep tempo like "3-0-1-0" (eccentric-pause-concentric-pause).
    var tempo: String?
    var notes: String?

    var session: WorkoutSession?

    @Relationship(deleteRule: .cascade, inverse: \SetLog.exercise)
    var setLogs: [SetLog]

    init(
        name: String,
        muscleGroup: String = "",
        order: Int,
        targetSets: Int,
        repRange: String,
        suggestedWeight: Double? = nil,
        restSeconds: Int,
        tempo: String? = nil,
        notes: String? = nil,
        setLogs: [SetLog] = []
    ) {
        self.name = name
        self.muscleGroup = muscleGroup
        self.order = order
        self.targetSets = targetSets
        self.repRange = repRange
        self.suggestedWeight = suggestedWeight
        self.restSeconds = restSeconds
        self.tempo = tempo
        self.notes = notes
        self.setLogs = setLogs
    }

    var orderedSetLogs: [SetLog] {
        setLogs.sorted { $0.setIndex < $1.setIndex }
    }

    /// Considered complete once the lifter has logged at least the prescribed number of sets.
    var isComplete: Bool { setLogs.count >= targetSets }

    /// Lower bound of the rep range, parsed from `repRange` (e.g. "8-12" -> 8).
    var repTargetLowerBound: Int {
        let firstNumber = repRange.split(whereSeparator: { !$0.isNumber })
            .first
            .flatMap { Int($0) }
        return firstNumber ?? 0
    }

    /// Upper bound of the rep range (e.g. "8-12" -> 12; "5" -> 5).
    var repTargetUpperBound: Int {
        let numbers = repRange.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return numbers.last ?? repTargetLowerBound
    }

    /// Heaviest weight ever logged for this exercise instance.
    var bestLoggedWeight: Double? {
        setLogs.compactMap(\.weight).max()
    }
}
