import Foundation

/// Part of a list, and how much of it there was.
///
/// **What it does.** Applies a limit to a list and builds the keys that report
/// it, so nothing can hand the coach part of a list without saying how much of
/// it there was.
///
/// **Why it exists.** Four places returned lists and answered this question four
/// different ways. `list_exercises` advertised a `limit`, never read it, and
/// returned all 412 movements. `exercise_history` had no limit at all, so a lift
/// trained weekly for two years arrives whole. `recent_sessions` applied a limit
/// and then reported the *truncated* count as `sessionCount`, which is the worst
/// of the three: ten-of-ten and ten-of-two-hundred read identically, and the
/// coach cannot tell that he is looking at a slice. Only the context resource
/// got it right, by hand. **A silently truncated list is the same failure as a
/// silently dropped key** — it reports success while the reader builds on
/// something that is not there.
///
/// **How it is used.** Build one with the elements *in the order they will be
/// reported*, then ask for `report(total:items:narrowing:entry:)`. The total it
/// states is the count before truncation, by construction, so a caller cannot
/// report the short number by mistake.
///
/// **Which end is kept is a decision, not a default.** `trained(in:)` is
/// newest-first, so its head is the recent work; `history(of:in:)` is
/// oldest-first, so its *tail* is. Taking the head of a lift's history would
/// hand back the twenty sessions furthest from what he is doing now and hide the
/// ones that matter, which is why `keeping` has no default and every caller
/// states it.
///
/// **What it depends on.** `JSONValue`. It sorts nothing and decides no order:
/// it is handed a list and told which end survives.
struct BoundedList<Element> {

    /// Which end of the list survives when there is more of it than the limit.
    enum Keeping {

        /// The start — a list already ordered with the interesting end first.
        case first

        /// The end — a list read oldest-first, where the recent rows are the
        /// ones the coach is planning against.
        case last
    }

    private let all: [Element]
    private let limit: Int
    private let keeping: Keeping

    /// - Parameters:
    ///   - all: every element, in the order they will be reported.
    ///   - limit: how many to return. **Raised to 1 if lower**, because a limit
    ///     of zero asks for a list with nothing in it, which is indistinguishable
    ///     from having nothing to report and is never what was meant. That is a
    ///     query argument being made sensible, not a prescribed value being
    ///     clamped — nothing in the record is touched.
    ///   - keeping: which end survives truncation.
    init(_ all: [Element], limit: Int, keeping: Keeping) {
        self.all = all
        self.limit = max(1, limit)
        self.keeping = keeping
    }

    /// The elements actually returned, in the order they were given.
    var shown: [Element] {
        guard all.count > limit else { return all }
        return switch keeping {
        case .first: Array(all.prefix(limit))
        case .last: Array(all.suffix(limit))
        }
    }

    /// Whether anything was left out.
    var isTruncated: Bool { all.count > limit }

    /// The keys that report this list.
    ///
    /// - Parameters:
    ///   - totalKey: what the untruncated count is called — `count`,
    ///     `performanceCount`, `sessionCount`. It is `all.count` and cannot be
    ///     anything else, which is the whole point of asking here.
    ///   - itemsKey: what the array is called.
    ///   - narrowing: what the coach can do about a list that was cut, in his
    ///     own vocabulary — which arguments narrow it. Said only when something
    ///     was actually cut.
    ///   - entry: how one element is written.
    func report(
        total totalKey: String, items itemsKey: String, narrowing: String,
        entry: (Element) -> JSONValue
    ) -> [String: JSONValue] {
        var keys: [String: JSONValue] = [
            totalKey: .integer(all.count),
            itemsKey: .array(shown.map(entry)),
        ]
        guard isTruncated else { return keys }
        // **Named as a fact and then an action, and it stops.** The count is
        // already above; this says what he is not seeing and how to see it.
        keys["truncated"] = .string(
            "\(all.count) matched and \(shown.count) are here. \(narrowing)")
        return keys
    }
}
