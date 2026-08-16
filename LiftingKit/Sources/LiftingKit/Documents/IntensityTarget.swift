import Foundation

/// The scale an intensity target is stated on.
///
/// **What it does.** Names the units a prescribed effort is measured in — RPE,
/// reps in reserve, a percentage of a one-rep max, or something this build has
/// never heard of. It is a label, not a measurement: nothing here says what a
/// value on a scale means, what range it runs over, or how one scale relates to
/// another.
///
/// **How it is used.** Read `IntensityTarget.scale` and report it beside the
/// value. `known` is what this build recognizes and is what a picker or a tool
/// schema should suggest — never what it accepts, since a coach may work in a
/// scale nobody here has heard of and that scale must arrive intact.
///
/// **Why the app never interprets it.** Whether an RPE of 8 is two reps in
/// reserve, or 80% of a one-rep max is heavy for this lifter, are training
/// judgements. This app keeps data and shows it; the judgements belong to
/// whoever wrote the plan.
///
/// Depends on: `ExtensibleTaxonomy`.
public struct IntensityScale: ExtensibleTaxonomy {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = Self.canonicalized(rawValue) }

    /// Rating of perceived exertion.
    public static let rpe = IntensityScale(rawValue: "rpe")
    /// Reps left in the tank at the end of the set.
    public static let repsInReserve = IntensityScale(rawValue: "rir")
    /// A share of the lifter's one-rep max, as a percentage.
    public static let percentOfOneRepMax = IntensityScale(rawValue: "percent1rm")

    public static let known: [IntensityScale] = [.rpe, .repsInReserve, .percentOfOneRepMax]
}

/// How hard a set is meant to be, on whatever scale the plan stated it.
///
/// **What it does.** Carries a prescribed effort as two facts: the scale it is
/// on and the target exactly as it was written. `"8"`, `"8-9"` and `"@9+"` are
/// all valid values, because a coach writes them all and none of them is this
/// app's to normalize.
///
/// **How it is used.** A `PlanDocumentExercise` or a `SetPrescription` carries
/// one; the snapshot reports it back beside the RPE the lifter actually logged,
/// which is the comparison every real progression decision turns on. An
/// exercise that states no target has `nil` — never a zero and never one
/// inferred from a load.
///
/// **What it depends on.** `IntensityScale` and `DocumentRefusal`. Nothing
/// converts between scales, bounds a value, or decides which scale is
/// meaningful: this type records, and a reader that wants a number parses the
/// value itself.
public struct IntensityTarget: Codable, Hashable, Sendable {

    /// What the value is measured in. Required — a bare number with no scale
    /// could only be read by guessing, and guessing here is prescribing.
    public let scale: IntensityScale
    /// The target exactly as written. A range stays a range: choosing an end of
    /// it would be the app deciding how hard to train.
    public let value: String

    public init(scale: IntensityScale, value: String) {
        self.scale = scale
        self.value = value
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case scale, value
    }

    /// Both fields are required, and an unknown key is refused rather than
    /// dropped — a discarded qualifier on an effort target is a prescription
    /// the lifter never sees.
    public init(from decoder: any Decoder) throws {
        try decoder.refuseUnknownKeys(besides: Set(CodingKeys.allCases.map(\.stringValue)))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scale = try container.decode(IntensityScale.self, forKey: .scale)
        value = try container.decode(String.self, forKey: .value)
    }
}
