import Foundation

/// Decides which of a split day's authored slots survive a session's time
/// budget.
///
/// Splits are authored at full length — six slots — while a thirty-minute
/// session holds three, so most weeks are truncated. Used by `SessionSkeleton`,
/// which hands over the whole week at once: the choice cannot be made a session
/// at a time, because whether dropping a pattern here is affordable depends on
/// whether it is trained somewhere else.
///
/// Keeping the leading slots and discarding the rest is the obvious rule and the
/// wrong one. It lets one pattern fill a whole short session, and it drops
/// patterns the week is required to train, because a pattern's second showing
/// tends to sit late in the list. So slots compete, in this order:
///
/// 1. The opening slot is kept outright — the heaviest movement, taken while
///    the lifter is freshest, is what the session is for.
/// 2. A pattern the week must train, in the last session that offers it and
///    only if nothing earlier has trained it. This is what makes a squat, a
///    hinge, and a pull survive even a three-slot week.
/// 3. Major patterns ahead of isolation work.
/// 4. Whatever is trained least so far this week, so coverage spreads instead
///    of doubling up.
/// 5. Of two patterns trained equally often, the one not already at the ceiling
///    a balance rule puts on it — this is what keeps pressing from outrunning
///    pulling when the week is cut short.
/// 6. Authored order, which is role order, so ties resolve towards the heavier
///    slot and the result is deterministic.
///
/// Throughout, no pattern may exceed the share of a session the rules allow it,
/// which is what makes that limit hold structurally rather than by luck.
///
/// Depends on: `AssemblyRulesProviding`, `SplitDay`, `SessionSlot`,
/// `MovementPattern`. No persistence, no catalog, no UI.
enum SlotSelection {

    /// The slots each day of `split` keeps when a session holds
    /// `slotsPerSession`, in the order they are performed.
    ///
    /// Returns one entry per day of `split`, each no longer than that day's
    /// authored slots.
    static func week(
        _ split: [SplitDay],
        slotsPerSession: Int,
        rules: some AssemblyRulesProviding
    ) -> [[SessionSlot]] {
        let majors = Set(rules.majorPatterns)
        let cap = perSessionCap(slots: slotsPerSession, share: rules.maxShareOfSessionPerPattern)
        let mustNotOutpace = Dictionary(
            rules.balanceRules.map { ($0.comparedTo, $0.atLeast) },
            uniquingKeysWith: { first, _ in first }
        )
        let lastChance = lastSessionAuthoring(rules.requiredWeeklyPatterns, in: split)
        let demand = Dictionary(
            rules.roleOrder.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let leastDemanding = rules.roleOrder.count

        var trained: [MovementPattern: Int] = [:]
        var week: [[SessionSlot]] = []

        for (session, day) in split.enumerated() {
            var chosen: [Int] = []
            var used: [MovementPattern: Int] = [:]

            func take(_ position: Int) {
                let pattern = day.slots[position].pattern
                chosen.append(position)
                used[pattern, default: 0] += 1
                trained[pattern, default: 0] += 1
            }

            /// Lower sorts first. See the type doc for what each rank means.
            func priority(_ position: Int) -> (Int, Int, Int, Int, Int) {
                let pattern = day.slots[position].pattern
                let count = trained[pattern, default: 0]
                let rescue = (lastChance[pattern] == session && count == 0) ? 0 : 1
                let isolation = majors.contains(pattern) ? 0 : 1
                var atCeiling = 0
                if let partner = mustNotOutpace[pattern] {
                    atCeiling = count >= trained[partner, default: 0] ? 1 : 0
                }
                return (rescue, isolation, count, atCeiling, position)
            }

            if slotsPerSession > 0, let opening = day.slots.indices.first {
                take(opening)
            }
            while chosen.count < slotsPerSession {
                let candidates = day.slots.indices.filter { position in
                    !chosen.contains(position)
                        && used[day.slots[position].pattern, default: 0] < cap
                }
                guard let next = candidates.min(by: { priority($0) < priority($1) }) else { break }
                take(next)
            }

            let performed = chosen.sorted { left, right in
                (demand[day.slots[left].role] ?? leastDemanding, left)
                    < (demand[day.slots[right].role] ?? leastDemanding, right)
            }
            week.append(performed.map { day.slots[$0] })
        }
        return week
    }

    /// The most slots one pattern may fill in a session this long.
    ///
    /// Rounded down, so a share of one half of three slots allows one rather
    /// than one and a half. Never below one: a session that holds slots at all
    /// must be able to put something in them, and a floor of one is arithmetic,
    /// not a training opinion.
    private static func perSessionCap(slots: Int, share: Double) -> Int {
        max(1, Int((share * Double(slots)).rounded(.down)))
    }

    /// For each required pattern, the last session of the week that offers it —
    /// its final chance to be trained, and so the point at which it outranks
    /// everything else competing for a slot.
    private static func lastSessionAuthoring(
        _ patterns: [MovementPattern],
        in split: [SplitDay]
    ) -> [MovementPattern: Int] {
        let required = Set(patterns)
        var last: [MovementPattern: Int] = [:]
        for (session, day) in split.enumerated() {
            for slot in day.slots where required.contains(slot.pattern) {
                last[slot.pattern] = session
            }
        }
        return last
    }
}
