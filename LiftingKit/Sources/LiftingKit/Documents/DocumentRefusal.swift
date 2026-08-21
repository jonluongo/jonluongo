import Foundation

/// Why an inbound document was refused instead of read.
///
/// **What it does.** Says, in one sentence a writer can act on, why `plan.json`
/// or `profile-update.json` was not taken in: a key no reader of this format
/// knows, a document written for a later format than this build reads, or two
/// statements in one document that cannot both be true.
///
/// **How it is used.** Thrown from the documents' own `init(from:)`, so the
/// macOS server and the phone refuse identically and a writer cannot learn one
/// answer from one and a different answer from the other. Catch it and show
/// `errorDescription`; the MCP server puts that same sentence in the tool
/// result, which is the only place the writer will read it.
///
/// **Why refuse at all.** A key that is quietly dropped tells the writer the
/// value landed when nothing of it survived — the lifter never sees the
/// prescription and nothing anywhere reports a problem. A refusal naming the
/// key is strictly better than a success that cannot be corrected.
///
/// Depends on: Foundation only.
public enum DocumentRefusal: Error, LocalizedError, Equatable, Sendable {

    /// A key this format does not have, and where in the document it sat.
    /// `location` is empty at the top level of the document.
    case unknownKey(String, location: String)

    /// The document states a format this build does not read.
    ///
    /// Refused whole rather than read for the parts this build recognizes: a
    /// partial read would discard the rest of it in exactly the silence this
    /// type exists to end.
    ///
    /// **One case, in both directions, because the asymmetry that justified two
    /// is gone.** There used to be a separate `earlierVersion` carrying a
    /// paragraph about routines, block labels and weekdays — why a version 5
    /// plan could not honestly be read as a version 6 one. `decided.md` scoped
    /// that to *exactly one break, at the reset*: it was safe only because the
    /// store reset at format 6, so no earlier document had anywhere to land.
    /// The reset happened, nothing older exists anywhere, and no version 5 plan
    /// will ever arrive again — so the paragraph was explaining a shape nobody
    /// can send to somebody who could not act on it either way.
    case versionMismatch(Int, understood: Int)

    /// A snapshot written in a format this build does not read — in either
    /// direction.
    ///
    /// **The snapshot is refused both ways, and the write formats are not.** A
    /// plan and a profile update are archives: the coach wrote them, they are
    /// the only copy, and an older one must go on being read forever. A snapshot
    /// is a cache — the phone regenerates the whole thing whenever the record
    /// changes — so an old one is not history, it is a stale file that will be
    /// replaced the moment the app opens. Reading it half-way would report a
    /// lifter who has trained less than he has, which is the one failure that
    /// arrives looking like a fact.
    ///
    /// It carries its own sentence rather than reusing `versionMismatch` because
    /// the audience is the other way round: a plan's refusal tells the coach to
    /// write an older format, and there is nothing he can do about a snapshot
    /// except rebuild the server or open the app.
    case snapshotVersionMismatch(Int, understood: Int)

    /// Two things the document says that cannot both be true, said in full.
    case contradiction(String)

    /// A key this format has, written in a shape it cannot be read in — such as
    /// a `null` where a dated series belongs. Refused rather than read as an
    /// absence, because "no readings" and "forget every reading" are different
    /// instructions and neither should be inferred from the other.
    case unreadableValue(String)

    public var errorDescription: String? { message }

    /// The refusal in one sentence a writer can act on.
    ///
    /// Separate from `errorDescription` only because that one is `String?` by
    /// protocol and this one never is: every caller here has something to say,
    /// and a caller forced to unwrap would have to invent a fallback sentence
    /// that could drift from these.
    public var message: String {
        switch self {
        case .unknownKey(let key, let location):
            "'\(key)' is not something this format can record\(Self.said(location)), so it "
                + "would have been dropped without anyone noticing. Nothing was taken in. "
                + "Send it under a key the format has, or leave it out and say it in a note."
        case .versionMismatch(let stated, let understood):
            // Both remedies in one line, because only one of them is the
            // lifter's: he can update the app, and he can ask for the plan
            // again. Which applies is obvious from the two numbers.
            "This plan is written in format version \(stated) and this build reads version "
                + "\(understood). Nothing was taken in. Update the app, or write the plan "
                + "again as version \(understood)."
        case .snapshotVersionMismatch(let stated, let understood):
            "The training log on disk is written in snapshot format version \(stated), and "
                + "this server reads version \(understood). Nothing was read, because taking "
                + "in only the parts this build recognizes would report a lifter who has "
                + "trained less than he has — which reads as a fact rather than as a failure. "
                + (stated > understood
                    ? "Rebuild the MCP server from the current source."
                    : "The phone wrote it with an older build: open the app once and it will "
                        + "write a current one.")
        case .contradiction(let detail):
            detail
        case .unreadableValue(let detail):
            detail
        }
    }

    /// Where a key sat, as a phrase, or nothing at all for the top level.
    private static func said(_ location: String) -> String {
        location.isEmpty ? "" : " (at \(location))"
    }
}

extension DocumentRefusal {

    /// Why an exercise inside a group cannot state a rest of its own.
    ///
    /// A group is performed as rounds and the rest is taken *after* the round —
    /// that clause is the whole definition of a superset. A rest attached to one
    /// member of it is a rest nobody takes, so it is refused with the key named
    /// rather than stored where it would silently do nothing.
    public static func restInsideGroup(exercise: String, location: String) -> DocumentRefusal {
        .contradiction(
            "'restSeconds' is not something an exercise inside a group can state"
                + "\(said(location)): a group is performed as rounds and the rest is taken after "
                + "the round, so a rest on '\(exercise)' alone would be a rest nobody takes. "
                + "Nothing was taken in. Move it to the group's own 'restSeconds', which is the "
                + "rest after each round.")
    }

    /// Why a plan may state only one block.
    ///
    /// **The coach writes a block at a time, and the routine grows.** He is
    /// meant to read what actually happened in the block just finished before
    /// prescribing the next — that reading is the whole of what he is for. A
    /// document carrying three blocks is a month written in advance of the
    /// evidence, and the two later ones will be rewritten or trained blind.
    ///
    /// Refused rather than trimmed to the first block, for the standing reason:
    /// taking part of a document in tells the writer his prescription landed
    /// when most of it did not.
    public static func severalBlocks(_ stated: [Int]) -> DocumentRefusal {
        .contradiction(
            "A plan states one block, and this one states \(stated.count) "
                + "(\(stated.map(String.init).joined(separator: ", "))). Nothing was taken in. "
                + "Write the next block on its own — blocks run continuously and never restart, "
                + "so send the one that follows what is already on the phone, and send the block "
                + "after it once you have seen how this one went.")
    }

    /// Why a group has to hold more than one exercise.
    ///
    /// One exercise performed with rest after it is an exercise, and the format
    /// already says that in one line. A 'group' of one would be the same
    /// prescription written in a shape that claims something it is not.
    public static func groupOfOne(stated: Int, location: String) -> DocumentRefusal {
        .contradiction(
            "A 'group' is two or more exercises performed back to back with the rest taken after "
                + "the round, and this one states \(stated)\(said(location)). Nothing was taken "
                + "in. Send at least two exercises in the group, or send the exercise on its own "
                + "with its own 'restSeconds'.")
    }

}

/// A key of whatever object is being read, whatever it is called.
///
/// Exists so a decoder can ask what keys are actually present rather than only
/// the ones it already knows — `KeyedDecodingContainer.allKeys` reports only
/// keys its own `CodingKey` type can represent, which is precisely blind to the
/// keys that would otherwise be dropped. Depends on: Foundation only.
private struct AnyDocumentKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension Decoder {

    /// Throws `DocumentRefusal.unknownKey` for the first key here that
    /// `accepted` does not name.
    ///
    /// Keys are checked in sorted order, so the same document always names the
    /// same key and a writer fixing one failure does not get a different one
    /// back for the same mistake.
    func refuseUnknownKeys(besides accepted: Set<String>) throws {
        let container = try self.container(keyedBy: AnyDocumentKey.self)
        let unknown = container.allKeys.map(\.stringValue).sorted()
            .first { !accepted.contains($0) }
        guard let unknown else { return }
        throw DocumentRefusal.unknownKey(unknown, location: documentLocation)
    }

    /// The path to what is being read, as a reader of the JSON would point at
    /// it: `weeks → 2 → days → 0 → exercises → 1`.
    ///
    /// Read by anything that refuses a value rather than a key — a group with
    /// one exercise in it, a rest inside a group — so every refusal points at
    /// the same place in the same words.
    var documentLocation: String {
        codingPath
            .map { $0.intValue.map(String.init) ?? $0.stringValue }
            .filter { !$0.isEmpty }
            .joined(separator: " → ")
    }
}
