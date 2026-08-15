import Testing
import Foundation
@testable import LiftingPlan

/// Rules a test can bend: every answer is supplied by the fixture, so a
/// property can be exercised against a rules file that will never ship.
///
/// Used to prove the parts of `SessionSkeleton` the bundled file cannot reach —
/// a role with no prescription, an experience adjustment large enough to drive
/// sets below zero. Depends on: `AssemblyRulesProviding`.
private struct FixtureRules: AssemblyRulesProviding {
    var version = 1
    var days: [SplitDay] = []
    var slots = 3
    var prescriptions: [SlotRole: RolePrescription] = [:]
    var adjustment = 0
    var roleOrder: [SlotRole] = [.primary, .secondary, .accessory, .finisher]
    var balanceRules: [BalanceRule] = []
    var requiredWeeklyPatterns: [MovementPattern] = []
    var majorPatterns: [MovementPattern] = []
    var target = 0
    var maxShareOfSessionPerPattern: Double = 1

    func split(forDayCount count: Int) -> [SplitDay] { days }
    func slotCount(forDurationMinutes minutes: Int) -> Int { slots }
    func prescription(for role: SlotRole) -> RolePrescription? { prescriptions[role] }
    func setAdjustment(for experience: ExperienceLevel) -> Int { adjustment }
    func targetWeeklyFrequency(forDayCount count: Int) -> Int { target }
    static func bundled(bundle: Bundle) throws -> FixtureRules { FixtureRules() }
}

/// The properties a generated week must hold at every combination of training
/// days and session length.
///
/// These assert programming rules, never the file's own literals: a test that
/// reads `sets` out of the JSON and checks it equals the JSON guards nothing.
/// The cross-product of day count against duration is deliberate — splits are
/// authored at six slots and a thirty-minute session keeps three, so every
/// coverage bug lives in the truncation, and a frequency assertion that only
/// runs at sixty minutes would green-light broken short sessions.
@Suite("Session skeleton")
struct SessionSkeletonTests {

    /// One per entry in the bundled duration table, so every slot budget is
    /// exercised rather than only the longest.
    private static let durations = [30, 45, 60, 90]
    private static let dayCounts = Array(1...6)

    private func rules() throws -> AssemblyRules { try AssemblyRules.bundled() }

    private func weekdays(_ count: Int) -> [Weekday] {
        Array(Weekday.displayOrder.prefix(count))
    }

    private func week(
        _ rules: AssemblyRules, dayCount: Int, minutes: Int,
        experience: ExperienceLevel = .intermediate
    ) throws -> [SessionSpec] {
        try SessionSkeleton.build(
            weekdays: weekdays(dayCount), durationMinutes: minutes,
            experience: experience, rules: rules
        )
    }

    private func patternCounts(_ week: [SessionSpec]) -> [MovementPattern: Int] {
        var counts: [MovementPattern: Int] = [:]
        for session in week where true {
            for slot in session.slots { counts[slot.pattern, default: 0] += 1 }
        }
        return counts
    }

    // MARK: - How often a pattern can possibly be trained

    /// The most times *every* major pattern can be trained in a week, derived
    /// from real capacity rather than read out of a day-count table.
    ///
    /// This is a supply-and-demand counting argument over the *authored* split,
    /// and it knows nothing about how `SessionSkeleton` chooses slots — which is
    /// what makes asserting against it meaningful rather than circular. For any
    /// set of patterns `P`, a session can emit at most `slots` slots and at most
    /// `cap` instances of any one pattern, so the whole week can supply at most
    /// `Σ min(slots, availability)` slot-instances to `P`; if they are shared
    /// among `|P|` patterns then some pattern gets no more than the average.
    /// The tightest such bound over every subset, capped by the frequency the
    /// rules actually target, is the honest guarantee.
    private func attainableFrequency(_ rules: AssemblyRules, dayCount: Int, slots: Int) -> Int {
        let split = rules.split(forDayCount: dayCount)
        let majors = rules.majorPatterns
        let cap = SessionSkeletonTests.cap(rules, slots: slots)
        var best = rules.targetWeeklyFrequency(forDayCount: dayCount)
        guard !majors.isEmpty, majors.count < 16 else { return best }

        for mask in 1..<(1 << majors.count) {
            let subset = majors.indices.filter { mask & (1 << $0) != 0 }.map { majors[$0] }
            var supply = 0
            for day in split {
                let available = subset.reduce(0) { running, pattern in
                    running + min(day.slots.filter { $0.pattern == pattern }.count, cap)
                }
                supply += min(slots, available)
            }
            best = min(best, supply / subset.count)
        }
        return best
    }

    /// The most slots one pattern may fill in a session of this length.
    private static func cap(_ rules: AssemblyRules, slots: Int) -> Int {
        max(1, Int((rules.maxShareOfSessionPerPattern * Double(slots)).rounded(.down)))
    }

    @Test("Every major pattern is trained as often as the week's capacity allows",
          arguments: dayCounts, durations)
    func majorPatternsMeetAttainableFrequency(dayCount: Int, minutes: Int) throws {
        let rules = try rules()
        let built = try week(rules, dayCount: dayCount, minutes: minutes)
        let counts = patternCounts(built)
        let attainable = attainableFrequency(
            rules, dayCount: dayCount, slots: rules.slotCount(forDurationMinutes: minutes)
        )
        #expect(!rules.majorPatterns.isEmpty)
        for pattern in rules.majorPatterns {
            #expect(
                counts[pattern, default: 0] >= attainable,
                """
                \(dayCount) days of \(minutes) minutes trains '\(pattern)' \
                \(counts[pattern, default: 0])x, below the \(attainable)x this week can hold.
                """
            )
        }
    }

    /// Guards the guarantee itself. A capacity bound that collapsed to zero
    /// everywhere would make the assertion above vacuously true, so the bound
    /// must rise with both training days and session length, and must reach the
    /// twice-weekly frequency the programming spec states outright wherever a
    /// full-length session is trained more than one day a week.
    @Test("The attainable frequency grows with days and duration, and reaches twice weekly")
    func attainableFrequencyIsNotVacuous() throws {
        let rules = try rules()
        func attainable(_ days: Int, _ minutes: Int) -> Int {
            attainableFrequency(rules, dayCount: days,
                                slots: rules.slotCount(forDurationMinutes: minutes))
        }
        for days in Self.dayCounts {
            for (shorter, longer) in zip(Self.durations, Self.durations.dropFirst()) {
                #expect(attainable(days, shorter) <= attainable(days, longer),
                        "\(days) days: a longer session buys less coverage than a shorter one.")
            }
        }
        for minutes in Self.durations {
            for (fewer, more) in zip(Self.dayCounts, Self.dayCounts.dropFirst()) {
                #expect(attainable(fewer, minutes) <= attainable(more, minutes),
                        "\(minutes) minutes: more training days buy less coverage than fewer.")
            }
        }
        // Stated by the programming spec, not read back from the rules file.
        for days in 2...6 {
            #expect(attainable(days, 90) >= 2,
                    "\(days) full-length days does not reach each major pattern twice a week.")
        }
        #expect(attainable(1, 90) >= 1)
    }

    @Test("Every required weekly pattern is trained, however short the sessions",
          arguments: dayCounts, durations)
    func requiredPatternsSurviveTruncation(dayCount: Int, minutes: Int) throws {
        let rules = try rules()
        let trained = Set(try week(rules, dayCount: dayCount, minutes: minutes)
            .flatMap(\.slots).map(\.pattern))
        #expect(!rules.requiredWeeklyPatterns.isEmpty)
        for pattern in rules.requiredWeeklyPatterns {
            #expect(trained.contains(pattern),
                    "\(dayCount) days of \(minutes) minutes never trains '\(pattern)'.")
        }
    }

    @Test("No pattern fills more than its allowed share of a session",
          arguments: dayCounts, durations)
    func noPatternDominatesASession(dayCount: Int, minutes: Int) throws {
        let rules = try rules()
        let share = rules.maxShareOfSessionPerPattern
        for session in try week(rules, dayCount: dayCount, minutes: minutes) {
            var used: [MovementPattern: Int] = [:]
            for slot in session.slots { used[slot.pattern, default: 0] += 1 }
            for (pattern, count) in used {
                #expect(
                    Double(count) <= share * Double(session.slots.count) + .ulpOfOne,
                    """
                    '\(pattern)' fills \(count) of \(session.slots.count) slots on \
                    '\(session.focus)' at \(dayCount) days of \(minutes) minutes.
                    """
                )
            }
        }
    }

    // MARK: - Shape

    @Test("Sessions are as long as the duration table says, and never longer than the split",
          arguments: dayCounts, durations)
    func slotCountFollowsTheDurationTable(dayCount: Int, minutes: Int) throws {
        let rules = try rules()
        let budget = rules.slotCount(forDurationMinutes: minutes)
        let built = try week(rules, dayCount: dayCount, minutes: minutes)
        #expect(built.count == dayCount)
        for (session, day) in zip(built, rules.split(forDayCount: dayCount)) {
            #expect(session.slots.count == min(budget, day.slots.count))
            #expect(session.focus == day.focus)
        }
    }

    @Test("A longer session never yields fewer slots", arguments: dayCounts)
    func slotCountIsMonotonicInDuration(dayCount: Int) throws {
        let rules = try rules()
        let lengths = try Self.durations.map { minutes in
            try week(rules, dayCount: dayCount, minutes: minutes).map(\.slots.count)
        }
        for (shorter, longer) in zip(lengths, lengths.dropFirst()) {
            for (a, b) in zip(shorter, longer) {
                #expect(a <= b, "A longer session gave \(b) slots where a shorter one gave \(a).")
            }
        }
        #expect(Set(lengths.flatMap { $0 }).count > 1, "Duration made no difference at all.")
    }

    @Test("Slots run heaviest first: primary leads, finisher closes",
          arguments: dayCounts, durations)
    func slotsAreOrderedByNeurologicalDemand(dayCount: Int, minutes: Int) throws {
        let rules = try rules()
        let rank = Dictionary(rules.roleOrder.enumerated().map { ($1, $0) },
                              uniquingKeysWith: { first, _ in first })
        for session in try week(rules, dayCount: dayCount, minutes: minutes) {
            let ranks = session.slots.compactMap { rank[$0.role] }
            #expect(ranks.count == session.slots.count, "A slot uses a role missing from roleOrder.")
            #expect(ranks == ranks.sorted(), "'\(session.focus)' is not ordered heaviest first.")
            if session.slots.contains(where: { $0.role == .finisher }) {
                #expect(session.slots.last?.role == .finisher,
                        "'\(session.focus)' does not close with its finisher.")
            }
            #expect(session.slots.first?.role == .primary,
                    "'\(session.focus)' does not open with a primary compound.")
        }
    }

    @Test("Every slot carries the prescription its role is worth",
          arguments: dayCounts, durations)
    func slotsCarryTheirRolePrescription(dayCount: Int, minutes: Int) throws {
        let rules = try rules()
        for session in try week(rules, dayCount: dayCount, minutes: minutes) {
            for slot in session.slots {
                let prescribed = try #require(rules.prescription(for: slot.role))
                #expect(slot.restSeconds == prescribed.restSeconds)
                #expect(slot.reps == prescribed.repRange)
                #expect(slot.reps.lowerBound > 0)
                #expect(slot.sets > 0)
            }
        }
    }

    @Test("Sessions land on the days the lifter chose, in week order")
    func sessionsLandOnTheChosenDays() throws {
        let rules = try rules()
        let chosen: [Weekday] = [.saturday, .tuesday, .thursday]
        let built = try SessionSkeleton.build(
            weekdays: chosen, durationMinutes: 60, experience: .intermediate, rules: rules
        )
        #expect(built.map(\.weekday) == [.tuesday, .thursday, .saturday])
        // A repeated day is one training day, not two.
        let repeated = try SessionSkeleton.build(
            weekdays: [.monday, .monday], durationMinutes: 60,
            experience: .intermediate, rules: rules
        )
        #expect(repeated.count == 1)
        #expect(try SessionSkeleton.build(
            weekdays: [], durationMinutes: 60, experience: .intermediate, rules: rules
        ).isEmpty)
    }

    // MARK: - Experience

    @Test("Experience moves set volume in one direction and never below one set",
          arguments: durations)
    func experienceAdjustsSetsWithoutErasingThem(minutes: Int) throws {
        let rules = try rules()
        let levels: [ExperienceLevel] = [.beginner, .intermediate, .advanced]
        let weeks = try levels.map { try week(rules, dayCount: 4, minutes: minutes, experience: $0) }
        let sets = weeks.map { $0.flatMap(\.slots).map(\.sets) }

        #expect(sets.allSatisfy { $0.allSatisfy { $0 >= 1 } })
        for (lighter, heavier) in zip(sets, sets.dropFirst()) {
            #expect(lighter.count == heavier.count)
            #expect(zip(lighter, heavier).allSatisfy { $0 <= $1 },
                    "More experience prescribed fewer sets.")
        }
        #expect(sets.first != sets.last, "Experience made no difference to volume.")
        // Slot shape must not shift with experience — only volume.
        #expect(weeks.map { $0.flatMap(\.slots).map(\.pattern) }.allSatisfy {
            $0 == weeks[0].flatMap(\.slots).map(\.pattern)
        })
    }

    @Test("A set count is never driven below one, however deep the adjustment")
    func setsNeverFallBelowOne() throws {
        var fixture = FixtureRules()
        fixture.days = [SplitDay(focus: "Made Up", slots: [
            SessionSlot(role: .primary, pattern: .squat)
        ])]
        fixture.prescriptions = [.primary: RolePrescription(sets: 2, reps: "5", restSeconds: 120)]
        fixture.adjustment = -99
        let built = try SessionSkeleton.build(
            weekdays: [.monday], durationMinutes: 60, experience: .beginner, rules: fixture
        )
        #expect(built.first?.slots.first?.sets == 1)
    }

    @Test("A slot whose role has no prescription is reported, never silently dropped")
    func aRoleWithNoPrescriptionThrows() {
        var fixture = FixtureRules()
        fixture.days = [SplitDay(focus: "Made Up", slots: [
            SessionSlot(role: .primary, pattern: .squat)
        ])]
        fixture.prescriptions = [:]
        #expect(throws: SkeletonError.self) {
            try SessionSkeleton.build(
                weekdays: [.monday], durationMinutes: 60, experience: .beginner, rules: fixture
            )
        }
    }

    // MARK: - Determinism

    @Test("The same request always produces the same week", arguments: dayCounts, durations)
    func buildIsDeterministic(dayCount: Int, minutes: Int) throws {
        let rules = try rules()
        let first = try week(rules, dayCount: dayCount, minutes: minutes)
        let second = try week(rules, dayCount: dayCount, minutes: minutes)
        #expect(first == second)
        // Order of the chosen days must not change the programming either.
        let shuffled = try SessionSkeleton.build(
            weekdays: weekdays(dayCount).reversed(), durationMinutes: minutes,
            experience: .intermediate, rules: rules
        )
        #expect(shuffled == first)
    }
}
