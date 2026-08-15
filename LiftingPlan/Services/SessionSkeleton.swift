import Foundation

/// One position in a planned session: the part it plays, the movement pattern
/// that fills it, and the volume prescribed for it.
///
/// Produced by `SessionSkeleton.build` and handed to exercise selection, which
/// picks a movement matching `pattern` without disturbing anything else here.
/// It names a pattern rather than an exercise on purpose: the skeleton is the
/// part of a plan that must be provably balanced, and balance is a property of
/// patterns. Depends on: `SlotRole`, `MovementPattern`, and `RepRange` from
/// Domain and Catalog. No persistence, no catalog lookup, no UI.
struct SlotSpec: Sendable, Equatable {
    let role: SlotRole
    let pattern: MovementPattern
    let sets: Int
    let reps: RepRange
    let restSeconds: Int
}

/// One planned training day: when it falls, what it trains, and the ordered
/// slots that make it up.
///
/// Read `slots` in order — they run heaviest first. `focus` is the split's own
/// label ("Push", "Lower Body") and is display text, not an identifier.
/// Depends on: `Weekday` from Domain and `SlotSpec`.
struct SessionSpec: Sendable, Equatable {
    let weekday: Weekday
    let focus: String
    let slots: [SlotSpec]
}

/// A skeleton that could not be built from the rules it was given.
///
/// Thrown rather than swallowed: a slot whose role carries no prescription
/// cannot be trained, and silently dropping it would hand the lifter a shorter
/// session than the rules describe with nothing to indicate why.
/// Depends on: `SlotRole`.
enum SkeletonError: Error, Equatable {
    case missingPrescription(SlotRole)
}

/// Builds the shape of a training week — which day trains what, how many slots
/// it holds, and the pattern and prescription each slot carries — without
/// choosing a single exercise.
///
/// Call `build` with the lifter's training days, session length, and experience.
/// The result is the skeleton exercise selection then fills. Keeping it
/// exercise-free is what makes balance checkable without a catalog, a database,
/// or a model.
///
/// Every number it uses is read from `AssemblyRulesProviding` — splits, slot
/// budgets, sets, reps, rest, and the balance opinions that decide what survives
/// a short session. Depends on: `AssemblyRulesProviding` and the Domain value
/// types. No persistence, no UI.
enum SessionSkeleton {

    /// Assembles a week.
    ///
    /// `weekdays` is deduplicated and put in week order, so the same set of days
    /// always yields the same programming whatever order the caller collected
    /// them in. The split is chosen by how many distinct days there are; if that
    /// exceeds the longest split the rules define, the surplus days go untrained
    /// rather than repeating a session.
    ///
    /// Throws `SkeletonError.missingPrescription` if a slot names a role the
    /// rules prescribe nothing for.
    static func build(
        weekdays: [Weekday],
        durationMinutes: Int,
        experience: ExperienceLevel,
        rules: some AssemblyRulesProviding
    ) throws -> [SessionSpec] {
        let days = orderedDistinct(weekdays)
        guard !days.isEmpty else { return [] }

        let split = rules.split(forDayCount: days.count)
        let budget = rules.slotCount(forDurationMinutes: durationMinutes)
        let selected = SlotSelection.week(split, slotsPerSession: budget, rules: rules)
        let adjustment = rules.setAdjustment(for: experience)

        var sessions: [SessionSpec] = []
        for (offset, weekday) in days.enumerated() {
            guard offset < split.count, offset < selected.count else { break }
            sessions.append(SessionSpec(
                weekday: weekday,
                focus: split[offset].focus,
                slots: try selected[offset].map {
                    try spec(for: $0, adjustment: adjustment, rules: rules)
                }
            ))
        }
        return sessions
    }

    private static func spec(
        for slot: SessionSlot,
        adjustment: Int,
        rules: some AssemblyRulesProviding
    ) throws -> SlotSpec {
        guard let prescribed = rules.prescription(for: slot.role) else {
            throw SkeletonError.missingPrescription(slot.role)
        }
        return SlotSpec(
            role: slot.role,
            pattern: slot.pattern,
            // A slot that survived truncation is work the lifter is going to do,
            // so experience may lighten it but can never erase it.
            sets: max(1, prescribed.sets + adjustment),
            reps: prescribed.repRange,
            restSeconds: prescribed.restSeconds
        )
    }

    /// The chosen days, without repeats, in the order a week reads.
    private static func orderedDistinct(_ weekdays: [Weekday]) -> [Weekday] {
        let chosen = Set(weekdays)
        return Weekday.displayOrder.filter(chosen.contains)
    }
}
