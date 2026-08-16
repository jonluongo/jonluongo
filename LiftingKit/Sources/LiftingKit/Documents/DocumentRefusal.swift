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

    /// The document states a format later than this build reads.
    ///
    /// Refused whole rather than read for the parts this build recognizes:
    /// a partial read would discard the rest of it in exactly the silence this
    /// type exists to end.
    case laterVersion(Int, understood: Int)

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
        case .laterVersion(let stated, let understood):
            "This document says it is written in format version \(stated), and this build "
                + "reads version \(understood). Nothing was taken in, because reading only the "
                + "parts this build recognizes would silently discard the rest. Write version "
                + "\(understood), or update the app."
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

    /// Why a dated series cannot be taken back with a `null`.
    ///
    /// Built here rather than at either call site because both clients answer
    /// this question: the phone refuses it while decoding a document, and the
    /// macOS server refuses it while reading the arguments of the call that
    /// would have written one. One sentence, so a writer cannot learn that a
    /// `null` is accepted from the tool and that it is refused from the app.
    public static func nulledSeries(_ series: ProfileSeries) -> DocumentRefusal {
        .unreadableValue(
            "'\(series.rawValue)' is a dated series, not a single value, so a null cannot take "
                + "it back — it would read either as recording nothing or as erasing every "
                + "entry, and there is no telling which was meant. Nothing was taken in. To "
                + "correct an entry, \(series.remedy); to add one, send just the new one.")
    }
}

/// The facts a `ProfileUpdate` carries as a series of dated records rather than
/// as a single value.
///
/// Two, and closed on purpose: this is the list of keys in one document format,
/// the way `CodingKeys` is, not a vocabulary that data may extend. Read it to
/// name a series in a refusal, and to say how a writer corrects an entry in it.
///
/// Depends on: Foundation only.
public enum ProfileSeries: String, Sendable, CaseIterable {
    case bodyweight
    case baselines

    /// What a writer does instead of nulling this series, in the words the
    /// refusal uses. Each record is filed under what it is about, so restating
    /// that one record is the correction.
    public var remedy: String {
        switch self {
        case .bodyweight: "state that day's reading again"
        case .baselines: "state that lift's baseline again"
        }
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
        throw DocumentRefusal.unknownKey(unknown, location: whereItSits)
    }

    /// The path to what is being read, as a reader of the JSON would point at
    /// it: `weeks → 2 → days → 0 → exercises → 1`.
    private var whereItSits: String {
        codingPath
            .map { $0.intValue.map(String.init) ?? $0.stringValue }
            .filter { !$0.isEmpty }
            .joined(separator: " → ")
    }
}
