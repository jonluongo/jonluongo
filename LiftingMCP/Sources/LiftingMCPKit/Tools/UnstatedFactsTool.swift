import Foundation
import LiftingKit

extension ToolRunner {

    /// Reports every fact the lifter's record can hold and which of them nobody
    /// has stated yet.
    ///
    /// **Why this is a tool and not only a resource.** The context resource has
    /// carried an `unstated` list for a while, and whether a client attaches a
    /// resource to a turn is the client's behaviour, not this server's. A list
    /// of empty fields that is never read is the same as no list at all, so the
    /// same answer is reachable by a call Claude can always make.
    ///
    /// **What it is and is not.** It states which fields the record has and
    /// which of them are empty. It does not say which of them matter for the
    /// plan about to be written, what order to ask them in, or that any of them
    /// must be known before prescribing anything — that would be this server
    /// deciding how coaching goes, which is the one thing it does not do.
    ///
    /// It reads the snapshot like every other reading tool, so a snapshot that
    /// is not there fails with that explanation rather than reporting all eight
    /// facts as unstated. Those two look identical in a report and are not the
    /// same thing: one is a lifter nobody has asked, the other is a file that
    /// has not been written.
    func unstatedFacts(in snapshot: TrainingSnapshot) -> ToolOutcome {
        .report(Self.factsReport(for: snapshot))
    }

    /// The record's capacity and its holes, in one shape.
    ///
    /// Both lists together are every fact the record can hold, which is what
    /// makes this a statement about the record rather than a list somebody
    /// curated. The unstated ones carry what each field holds, because a name on
    /// its own does not say what would go in it; the stated ones are named only,
    /// since their values are already in the context resource.
    static func factsReport(for snapshot: TrainingSnapshot) -> JSONValue {
        [
            "snapshotGeneratedAt": .date(snapshot.generatedAt),
            "unstated": .array(
                LifterFacts.unstated(in: snapshot).map {
                    ["fact": .string($0.name), "holds": .string($0.holds)]
                }),
            "stated": .array(LifterFacts.stated(in: snapshot).map { .string($0.name) }),
            "statedWith": .string(ToolCatalog.updateProfile),
            "note": .string(note),
        ]
    }

    /// What the two lists mean, and what they do not.
    ///
    /// The last sentence is the point of the whole tool: this reports empty
    /// fields, and every judgement about them is the reader's.
    private static let note = """
        Together these are every fact this record can hold about the lifter. A \
        fact under 'unstated' has no value on record: the app has no setup \
        screen and asks him nothing, so nobody has said — which is not an answer \
        of 'none' and not a default. \(ToolCatalog.updateProfile) is what \
        records one, and it merges, so one fact at a time is fine. Which of \
        these matter for what you are about to do, whether to ask about them at \
        all, and in what order, is yours to judge; this only says which fields \
        are empty.
        """
}
