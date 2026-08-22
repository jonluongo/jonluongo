import Foundation

/// A plan the phone turned away, said back to the coach who wrote it.
///
/// **What it does.** Carries the last plan the phone refused — when, and the
/// refusal verbatim — so the coach learns that his prescription never landed.
///
/// **How it is used.** The phone records one when an arriving plan is refused
/// and clears it when a plan is taken in; `SnapshotExporter` writes it and the
/// server's context resource reports it.
///
/// **Why it exists at all.** There are two checkpoints and the coach is present
/// at only one. `write_plan` refuses a format error or an invented exercise ID
/// while he is still there, and he fixes it in the same breath. The second
/// checkpoint is the phone, which alone knows what has been *trained* — and it
/// runs long after `write_plan` answered *written*. A plan rewriting a block the
/// user has already logged against is refused there, correctly, and until this
/// existed nothing carried that fact back: the coach believed a block was
/// prescribed that the phone had thrown away whole, and the only witness was an
/// alert on a phone he cannot see.
///
/// **The message is the coach's, not the user's.** The phone shows the user a
/// short line, because he did not write the plan and cannot fix it. What travels
/// here is the refusal as written for its author — naming the block, the key or
/// the ID — because he is the one who can act on it, and length costs him
/// nothing.
///
/// **What it depends on.** Foundation.
public struct SnapshotRefusal: Codable, Hashable, Sendable {

    /// When the phone refused it.
    public let at: Date
    /// The refusal, exactly as it was written for the coach.
    public let reason: String

    public init(at: Date, reason: String) {
        self.at = at
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case at, reason
    }

    public init(from decoder: any Decoder) throws {
        try decoder.refuseUnknownKeys(besides: Set(CodingKeys.allCases.map(\.stringValue)))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        at = try container.decode(Date.self, forKey: .at)
        reason = try container.decode(String.self, forKey: .reason)
    }
}
