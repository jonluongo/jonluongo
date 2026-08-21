import Foundation

/// What one set is meant to be: its reps, its load, how hard it should feel,
/// and anything to say about it.
///
/// **What it does.** Lets a prescription say that one set differs from the
/// next — a drop set, a ramp, a back-off set, a last set taken to failure. Every
/// field is optional and `nil` means *this set did not state it*, which is not
/// the same as stating nothing: an exercise states a prescription for its sets,
/// and a set that adds nothing of its own is prescribed exactly that.
///
/// **How it is used.** Two places share this one type, so the vocabulary cannot
/// drift: a `PlanDocumentExercise` lists them when its sets differ, and the app
/// stores them. Nothing restates them on the way back out — the snapshot carries
/// the document itself, which is where they were stated. Read `PlanDocumentExercise.prescribedSets` rather than these raw
/// values when you want what a set actually prescribes — that is where a set's
/// own statements and the exercise's are put together, by `everySet(...)`
/// below.
///
/// **What it depends on.** `Mass`, `IntensityTarget`, `DocumentRefusal`. It
/// judges nothing: a load is not turned into an intensity, an intensity is not
/// turned into a load, and no absent value is filled with a number the app
/// chose.
public struct SetPrescription: Codable, Hashable, Sendable {

    /// This set's rep target as written — `"5"`, `"8-12"`, `"AMRAP"`. `nil`
    /// when the set did not state one of its own.
    public let repRange: String?
    /// The load for this set, in the unit it was written in. `nil` when the set
    /// did not state one of its own.
    public let suggestedLoad: Mass?
    /// How hard this set is meant to be. `nil` when the set did not state a
    /// target of its own — never a zero, and never inferred from the load.
    public let intensity: IntensityTarget?
    /// Anything about this set in particular, such as "last set AMRAP". `nil`
    /// when there is none. An exercise's own note stays on the exercise; a set
    /// never inherits it, because a note about the movement is not a note about
    /// one set of it.
    public let notes: String?
    /// Whether this set is a warm-up.
    ///
    /// **The coach could not say this before.** `isWarmup` appeared nowhere in
    /// the plan document: `SetSeeding` hardcoded `false` for everything
    /// prescribed, and only a set the lifter added himself was ever marked. So
    /// *"ramp three sets to your top set"* — an ordinary thing for a coach to
    /// say — could not be written down, and the app's answer was that the
    /// lifter adds his own. That was the app quietly owning a piece of the
    /// prescription.
    ///
    /// It is stated per set and **never inherited from the exercise**: an
    /// exercise is not a warm-up, some of its sets are.
    public let isWarmup: Bool

    public init(
        repRange: String? = nil, suggestedLoad: Mass? = nil,
        intensity: IntensityTarget? = nil, notes: String? = nil,
        isWarmup: Bool = false
    ) {
        self.repRange = repRange
        self.suggestedLoad = suggestedLoad
        self.intensity = intensity
        self.notes = notes
        self.isWarmup = isWarmup
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case repRange, suggestedLoad, intensity, notes, isWarmup
    }

    /// Nothing is required: `{}` is a legitimate set, meaning "the same as this
    /// exercise prescribes". A key this format does not have is refused with
    /// the key named, as everywhere else in this format.
    public init(from decoder: any Decoder) throws {
        try decoder.refuseUnknownKeys(besides: Set(CodingKeys.allCases.map(\.stringValue)))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repRange = try container.decodeIfPresent(String.self, forKey: .repRange)
        suggestedLoad = try container.decodeIfPresent(Mass.self, forKey: .suggestedLoad)
        intensity = try container.decodeIfPresent(IntensityTarget.self, forKey: .intensity)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        isWarmup = try container.decodeIfPresent(Bool.self, forKey: .isWarmup) ?? false
    }

    /// Written out by hand so a working set does not carry `"isWarmup": false`.
    /// Most sets are working sets, and a key that states the default on every
    /// one of them is noise in a document a person reads.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(repRange, forKey: .repRange)
        try container.encodeIfPresent(suggestedLoad, forKey: .suggestedLoad)
        try container.encodeIfPresent(intensity, forKey: .intensity)
        try container.encodeIfPresent(notes, forKey: .notes)
        if isWarmup { try container.encode(true, forKey: .isWarmup) }
    }

    /// What this set asks for, read once.
    ///
    /// **Computed rather than stored, deliberately, and only for now.** The
    /// prescription's measure is moving from text to `Target`, and 21 files read
    /// this type; introducing a second stored field beside `repRange` would give
    /// the format two ways to say one thing while they migrate. So this is
    /// derived from what is already there, every reader can move to it one at a
    /// time, and when the last one has, `target` becomes the stored value and
    /// `repRange` is what disappears.
    ///
    /// `nil` when the set stated no target of its own — and, until the wire
    /// carries a `Target` directly, also when what it stated could not be read.
    /// Refusing an unreadable target is the wire's job, and it starts doing it
    /// when the wire changes.
    public var target: Target? {
        repRange.flatMap(Target.init(shorthand:))
    }
}

extension SetPrescription {

    /// Every set an exercise prescribes, each stated in full and in order.
    ///
    /// Two shapes reach this, and they answer the same question. When the
    /// exercise prescribed the same work throughout, `stated` is empty and
    /// `count` sets are returned, all carrying the exercise's own reps, load and
    /// intensity. When the exercise listed its sets one at a time, each listed
    /// set is returned with anything it did not state taken from the exercise's.
    ///
    /// **That fallback is reading the plan, not filling a gap.** An exercise
    /// that says `repRange: "5"` and then lists three loads has stated the reps
    /// for all three sets; making the writer repeat `"5"` three times is a tax
    /// on every plan, and a format that is tedious to write gets written badly.
    /// Nothing is ever supplied that the plan did not state somewhere: an
    /// unstated rep range stays `nil`, an unstated load stays `nil`, and an
    /// unstated intensity stays `nil`.
    ///
    /// A `count` of zero or less prescribes no sets. The count itself is
    /// recorded wherever it came from exactly as written — this only declines to
    /// build sets that were never asked for.
    public static func everySet(
        stated: [SetPrescription],
        count: Int,
        repRange: String,
        suggestedLoad: Mass?,
        intensity: IntensityTarget?
    ) -> [SetPrescription] {
        let shared = SetPrescription(
            // An empty rep range is how this format has always said "none was
            // prescribed"; it stays an absence here rather than becoming a
            // target of no reps.
            repRange: repRange.isEmpty ? nil : repRange,
            suggestedLoad: suggestedLoad,
            intensity: intensity
        )
        guard !stated.isEmpty else {
            return count > 0 ? Array(repeating: shared, count: count) : []
        }
        return stated.map { $0.completed(by: shared) }
    }

    /// This set with whatever it did not state taken from `shared`. Its own
    /// note is kept and never replaced: a note belongs to the set that wrote it.
    ///
    /// So does its own `isWarmup`. An exercise is not a warm-up — some of its
    /// sets are — so there is nothing on `shared` for a set to inherit here, and
    /// a ramp is exactly a list of sets that disagree about it.
    private func completed(by shared: SetPrescription) -> SetPrescription {
        SetPrescription(
            repRange: repRange ?? shared.repRange,
            suggestedLoad: suggestedLoad ?? shared.suggestedLoad,
            intensity: intensity ?? shared.intensity,
            notes: notes,
            isWarmup: isWarmup
        )
    }
}
