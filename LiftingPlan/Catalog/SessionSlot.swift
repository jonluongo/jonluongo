import Foundation

/// The vocabulary a split is written in: the parts a session is built from and
/// the prescriptions attached to them.
///
/// These are the decoded shapes of `assembly-rules.json`; read them through
/// `AssemblyRulesProviding` rather than decoding the file yourself. They are
/// separated from `AssemblyRules.swift` so the file that loads and answers
/// questions about the rules stays about loading and answering. Depends on:
/// the taxonomies and `RepRange` from Domain.

/// The part a slot plays in a session's running order, and therefore how hard
/// it is prescribed.
///
/// Read it off a `SessionSlot` and look the sets/reps/rest up with
/// `AssemblyRulesProviding.prescription(for:)`. Extensible rather than a closed
/// `enum` so a later rules file can introduce a role (a warm-up, a superset
/// partner) without an older build refusing to decode. Depends on:
/// `ExtensibleTaxonomy`.
struct SlotRole: ExtensibleTaxonomy {
    let rawValue: String
    init(rawValue: String) { self.rawValue = Self.canonicalized(rawValue) }

    /// The heaviest movement of the session, taken first while the lifter is fresh.
    static let primary = SlotRole(rawValue: "primary")
    /// A second compound, on a different pattern from the primary.
    static let secondary = SlotRole(rawValue: "secondary")
    /// Isolation work: moderate to high reps, short rest.
    static let accessory = SlotRole(rawValue: "accessory")
    /// Optional closing work — a carry, a flexion, a rotation.
    static let finisher = SlotRole(rawValue: "finisher")

    static let known: [SlotRole] = [.primary, .secondary, .accessory, .finisher]
}

/// One position in a session: what part it plays and which movement pattern
/// fills it.
///
/// Written in the rules file as `"role:pattern"` (`"primary:squat"`), because a
/// split day is far easier to read and edit as a list of short strings than as
/// a list of objects. Plan generation walks a day's slots in order and asks the
/// catalog for an exercise matching each pattern. Depends on: `SlotRole`,
/// `MovementPattern`.
struct SessionSlot: Codable, Hashable, Sendable, CustomStringConvertible {

    let role: SlotRole
    let pattern: MovementPattern

    init(role: SlotRole, pattern: MovementPattern) {
        self.role = role
        self.pattern = pattern
    }

    /// Decodes `"role:pattern"`.
    ///
    /// Unrecognized role or pattern *values* round-trip intact — that is the
    /// extensible-taxonomy contract. A malformed *shape* (no colon, or either
    /// side blank) is a different thing entirely and throws, because a slot
    /// that names no pattern can never be filled and silently dropping it
    /// would shorten a session without anyone noticing.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let separator = raw.firstIndex(of: ":") else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Slot '\(raw)' is not written as 'role:pattern'."
            )
        }
        let role = SlotRole(rawValue: String(raw[raw.startIndex..<separator]))
        let pattern = MovementPattern(rawValue: String(raw[raw.index(after: separator)...]))
        guard !role.rawValue.isEmpty, !pattern.rawValue.isEmpty else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Slot '\(raw)' leaves its role or its pattern blank."
            )
        }
        self.init(role: role, pattern: pattern)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    var description: String { "\(role.rawValue):\(pattern.rawValue)" }
}

/// One training day of a split: a display label and the ordered slots that
/// make up the session.
///
/// Slots are listed heaviest first and at full length; a session shorter than
/// the full list keeps the leading slots, so the time budget costs the lifter
/// the least important work rather than the most important. Depends on:
/// `SessionSlot`.
struct SplitDay: Codable, Hashable, Sendable {
    let focus: String
    let slots: [SessionSlot]
}

/// How many slots a session of at most `upTo` minutes is worth.
///
/// Read through `AssemblyRulesProviding.slotCount(forDurationMinutes:)` rather
/// than directly. Rest periods, not exercise count, are what actually consume a
/// session, which is why the budget is expressed in minutes. Depends on:
/// Foundation only.
struct SlotBudget: Codable, Hashable, Sendable {
    let upTo: Int
    let slots: Int
}

/// The sets, reps, and rest prescribed for one slot role.
///
/// Obtained from `AssemblyRulesProviding.prescription(for:)` while assembling a
/// session. `reps` stays the free text the file wrote so it can be shown and
/// persisted verbatim; `repRange` is the parsed form, produced by the one rep
/// parser this project has. Depends on: `RepRange`.
struct RolePrescription: Codable, Hashable, Sendable {
    let sets: Int
    let reps: String
    let restSeconds: Int

    /// The parsed bounds of `reps`, via `RepRange` — never a second parser.
    var repRange: RepRange { RepRange(reps) }
}

/// A rule that one pattern must be trained at least as much as another over a
/// week, e.g. horizontal pull at least as often as horizontal press.
///
/// Checked against an assembled week by plan generation. Stated as data because
/// which pairs to guard is a training opinion that should be tunable without a
/// code change. Depends on: `MovementPattern`.
struct BalanceRule: Codable, Hashable, Sendable {
    let atLeast: MovementPattern
    let comparedTo: MovementPattern
}
