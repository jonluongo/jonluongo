import Foundation

/// One entry of a training day: an exercise on its own, or a group of exercises
/// performed back to back.
///
/// **What it does.** Gives a day's `exercises` list two shapes rather than one,
/// the way `sets` is either a count or a list. An entry is an exercise object,
/// exactly as it has always been, or an object stating `group` — and because the
/// group *contains* its exercises rather than labelling them, a half-formed
/// grouping cannot be written at all: two exercises at opposite ends of a day
/// cannot claim one group, and order is inherent rather than asserted.
///
/// **How it is used.** `PlanDocumentDay.entries` holds these in the order the
/// work is to be done. Read `PlanDocumentDay.exercises` when all you want is the
/// movements — checking every `ExerciseID` against the catalog, say — and read
/// `entries` when the grouping matters, which is when it is being stored,
/// rendered or reported back.
///
/// **What it depends on.** `PlanDocumentExercise` and `PlanDocumentGroup`. It
/// decides nothing: the app never groups anything, and a day whose entries are
/// all bare exercises is exactly the day this format has always written.
public enum PlanDocumentEntry: Codable, Hashable, Sendable {

    /// One movement, performed and rested on its own.
    case exercise(PlanDocumentExercise)

    /// Two or more movements performed as rounds, resting after the round.
    case group(PlanDocumentGroup)

    /// The movements this entry prescribes, in order — one for an exercise,
    /// every member for a group.
    public var exercises: [PlanDocumentExercise] {
        switch self {
        case .exercise(let exercise): [exercise]
        case .group(let group): group.exercises
        }
    }

    /// The group this entry is, or `nil` when it is a single exercise.
    public var group: PlanDocumentGroup? {
        switch self {
        case .exercise: nil
        case .group(let group): group
        }
    }

    /// The one key that tells the two shapes apart.
    private enum GroupKey: String, CodingKey {
        case group
    }

    /// An object stating `group` is a group and anything else is an exercise.
    ///
    /// Distinguished by the key rather than by trying one shape and falling back
    /// to the other: a refusal from inside a group — an unknown key, a rest
    /// where none can go — must reach the writer as itself rather than being
    /// swallowed by a second attempt to read the same object as an exercise.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: GroupKey.self)
        if container.contains(.group) {
            self = .group(try PlanDocumentGroup(from: decoder))
        } else {
            self = .exercise(try PlanDocumentExercise(from: decoder))
        }
    }

    /// Written back in the shape it came in. The enum itself adds no key: an
    /// exercise encodes as the exercise object it is.
    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .exercise(let exercise): try exercise.encode(to: encoder)
        case .group(let group): try group.encode(to: encoder)
        }
    }
}

/// Two or more exercises performed back to back, resting only after the group.
///
/// **What it does.** Says the one thing a flat list of exercises cannot: that
/// these movements are performed as rounds. Two is a superset, three a tri-set,
/// more a giant set — the same structure with different counts, which is why
/// this carries a group of any size rather than a special case for pairs. The
/// unit of work becomes the round: round one is every member once, then round
/// two.
///
/// **How it is used.** Written by Claude inside a day's `exercises`, as
/// `{ "group": [ … ], "restSeconds": 90 }`. The app stores the members in order
/// and the logging screen draws one card per group with the rounds interleaved.
/// Nothing in the app ever creates one — a superset exists because the plan said
/// so.
///
/// **What it depends on.** `PlanDocumentExercise` and `DocumentRefusal`.
///
/// Two things are refused rather than read around. A group of fewer than two
/// exercises is not a group, and a member stating a `restSeconds` of its own
/// contradicts what a group *is* — the rest comes after the round, so a rest
/// inside one is a rest nobody takes.
public struct PlanDocumentGroup: Codable, Hashable, Sendable {

    /// The movements of the group, in the order they are performed within each
    /// round. Two or more, always.
    public let exercises: [PlanDocumentExercise]

    /// Rest after each round, in seconds. `nil` when the plan prescribed none —
    /// not zero, which would read as "rest none".
    public let restSeconds: Int?

    public init(exercises: [PlanDocumentExercise], restSeconds: Int? = nil) {
        self.exercises = exercises
        self.restSeconds = restSeconds
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case exercises = "group"
        case restSeconds
    }

    /// Both checks name what is wrong and take nothing in, as everywhere else in
    /// this format. They are made after the members decode, so an unknown key
    /// inside a member is still reported as the unknown key it is.
    public init(from decoder: any Decoder) throws {
        try decoder.refuseUnknownKeys(besides: Set(CodingKeys.allCases.map(\.stringValue)))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exercises = try container.decode([PlanDocumentExercise].self, forKey: .exercises)
        restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds)

        guard exercises.count > 1 else {
            throw DocumentRefusal.groupOfOne(
                stated: exercises.count, location: decoder.documentLocation)
        }
        if let resting = exercises.first(where: { $0.restSeconds != nil }) {
            throw DocumentRefusal.restInsideGroup(
                exercise: resting.displayName, location: decoder.documentLocation)
        }
    }
}
