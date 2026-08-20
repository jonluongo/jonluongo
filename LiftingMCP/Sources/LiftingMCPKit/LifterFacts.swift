import Foundation
import LiftingKit

/// One fact the lifter's record can hold, and how to tell whether anybody has
/// stated it.
///
/// **What it does.** Names a fact — `equipment`, `bodyweight`, `goal` — says in
/// a sentence what the record holds under that name, and answers whether the
/// record currently holds it. That is the whole of it. It does not say whether
/// the fact matters, when to ask for it, or what to do once it is known: those
/// are training decisions and they belong to Claude, not to this server.
///
/// **How it is used.** Through `LifterFacts`, which runs every known fact over
/// one snapshot. The `unstated_facts` tool, the context resource and
/// `write_plan`'s report all read that one answer, so three reports of what is
/// missing cannot disagree with each other.
///
/// **What it depends on.** `TrainingSnapshot` from LiftingKit. Every `name` is
/// also a key `ProfileUpdate` can hold, so a fact a report names is one
/// `update_profile` can actually close — `LifterFactsTests` is the guard on
/// that, and on a fact added to the document but not to this list.
public struct LifterFact: Sendable {

    /// The fact's name, which is also the `update_profile` argument that states
    /// it.
    public let name: String

    /// What the record holds under that name, in one sentence.
    public let holds: String

    private let stated: @Sendable (TrainingSnapshot) -> Bool

    init(
        _ name: String, _ holds: String,
        stated: @escaping @Sendable (TrainingSnapshot) -> Bool
    ) {
        self.name = name
        self.holds = holds
        self.stated = stated
    }

    /// Whether this snapshot holds a value for the fact.
    ///
    /// `false` means nobody has stated it. It never means the answer is none:
    /// the app asks the lifter nothing, so an empty field is a conversation that
    /// has not happened.
    public func isStated(in snapshot: TrainingSnapshot) -> Bool { stated(snapshot) }
}

/// Every fact the lifter's record can hold, and which of them a given snapshot
/// is currently empty on.
///
/// **What it does.** Answers one question — what does this record not know? —
/// from the snapshot itself. It is datakeeping: the app knows which of its own
/// fields are empty and says so. Nothing here ranks the facts, orders them, or
/// ties one to a kind of plan.
///
/// **How it is used.** `unstated(in:)` for the empty fields and `stated(in:)`
/// for the filled ones; together they are every fact the record can hold, which
/// is what makes a report of the two a complete statement of the record's
/// capacity rather than a list somebody curated.
///
/// **What it depends on.** `LifterFact` and `TrainingSnapshot`.
public enum LifterFacts {

    public static let equipment = LifterFact(
        "equipment",
        "What he owns, as an open set of equipment types — not a tier. "
            + "\(ToolCatalog.listExercises) narrows the catalog to it.",
        stated: { $0.profile?.availableEquipment != nil })

    public static let experience = LifterFact(
        "experience",
        "How much training he has behind him, in his own words.",
        stated: { $0.profile?.experience != nil })

    public static let goal = LifterFact(
        "goal",
        "What he is training for, in his own words.",
        stated: { $0.profile.map { !$0.goal.isEmpty } ?? false })

    public static let constraints = LifterFact(
        "constraints",
        "Injuries and limitations, in his own words.",
        stated: { $0.profile.map { !$0.constraints.isEmpty } ?? false })

    public static let bodyweight = LifterFact(
        "bodyweight",
        "What he weighs, as a dated series rather than one number.",
        stated: { latestBodyweight(in: $0) != nil })

    public static let baselines = LifterFact(
        "baselines",
        "What he can already do on a lift, before any of it is logged.",
        stated: { !$0.baselines.isEmpty })

    public static let preferredDurationMinutes = LifterFact(
        "preferredDurationMinutes",
        "How long he says a session can run.",
        stated: { $0.profile?.preferredDurationMinutes != nil })

    /// Every fact, in a fixed order so two runs over the same record name them
    /// the same way round. The order is the order they are declared in and means
    /// nothing else — it is not a sequence to ask them in.
    public static let known: [LifterFact] = [
        equipment, experience, goal, constraints,
        bodyweight, baselines, preferredDurationMinutes,
    ]

    /// The facts this record holds no value for.
    public static func unstated(in snapshot: TrainingSnapshot) -> [LifterFact] {
        known.filter { !$0.isStated(in: snapshot) }
    }

    /// The facts this record does hold a value for.
    public static func stated(in snapshot: TrainingSnapshot) -> [LifterFact] {
        known.filter { $0.isStated(in: snapshot) }
    }

    /// The most recent bodyweight on record, wherever it was written.
    ///
    /// A profile carries the last reading and the series carries all of them,
    /// and they are read in that order here so the context resource's value and
    /// this survey's verdict on `bodyweight` cannot disagree — one reporting a
    /// weight while the other calls it unstated is the exact confusion this
    /// whole survey exists to prevent.
    public static func latestBodyweight(in snapshot: TrainingSnapshot) -> Mass? {
        snapshot.profile?.bodyweight ?? snapshot.bodyMetrics.last?.bodyweight
    }

    /// The `update_profile` keys deliberately left out of the survey — the
    /// document's own list, not a second one kept here.
    ///
    /// Checked against `ProfileUpdate.statedKeys` by the tests, so a fact added
    /// to the document lands on one side of this line or fails the build rather
    /// than quietly going unreported. The two avoided lists are the enforceable
    /// half of `constraints`, which is surveyed. See
    /// `ProfileUpdate.unsurveyableKeys` for why each is out.
    public static let unsurveyedKeys = ProfileUpdate.unsurveyableKeys
}
