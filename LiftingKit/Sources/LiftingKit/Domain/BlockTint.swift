import Foundation

/// The colour a block is known by, chosen by whoever wrote it.
///
/// **What it does.** Names one of a closed set of tints the app can draw. The app
/// owns the set and refuses anything outside it; the coach picks which one a
/// block gets, the same way he picks its exercises from a catalog he did not
/// write and its sessions' marks from `SessionIcon`.
///
/// **Why he picks rather than the app.** A block's identity is its author's:
/// deriving a colour from the title or from a hash would be the app labelling
/// something it did not name. And a colour the *lifter* chose would be the app
/// asking him a question, which it does not do.
///
/// **How it is used.** `PlanDocument.tint` carries it in, `TrainingPlan` stores
/// the raw name, `SnapshotPlan` carries it back so a later plan can avoid
/// repeating the colour of the one before it, and the blocks list draws it. The
/// name is the app's own — `rust`, `moss` — never a hex: which shade a name
/// resolves to is this app's business and must not be a change to the format the
/// coach writes.
///
/// **A block with no tint is ordinary, not broken.** Absent is the common case
/// and draws the neutral the list has always used.
///
/// **What it depends on.** Foundation. The raw value round-trips whatever it is
/// handed, so a document written by a later build reaches the refusal with its
/// name intact.
public struct BlockTint: RawRepresentable, Codable, Hashable, Sendable {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static let slate = BlockTint(rawValue: "slate")
    public static let rust = BlockTint(rawValue: "rust")
    public static let moss = BlockTint(rawValue: "moss")
    public static let plum = BlockTint(rawValue: "plum")
    public static let ochre = BlockTint(rawValue: "ochre")
    public static let teal = BlockTint(rawValue: "teal")
    public static let clay = BlockTint(rawValue: "clay")
    public static let indigo = BlockTint(rawValue: "indigo")

    /// Every tint this build can draw, in the order the tool schema lists them.
    ///
    /// The schema is built from this array rather than retyping the names, so a
    /// tint added here is offered to the coach in the same commit and one
    /// removed stops being offered.
    public static let all: [BlockTint] = [
        .slate, .rust, .moss, .plum, .ochre, .teal, .clay, .indigo,
    ]

    /// Whether this build can draw it. `PlanImporter` asks before storing.
    public var isKnown: Bool { Self.all.contains(self) }
}
