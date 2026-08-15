import Testing
import Foundation
@testable import LiftingPlan

/// A rules fixture that reports a version no bundled file will ever carry, and
/// answers every other question emptily.
///
/// Its only job is to prove the seam: a type that is not `AssemblyRules` can
/// conform to `AssemblyRulesProviding` and vary `version`, which is what a
/// service needs in order to stamp the rules generation it built a plan from.
/// Depends on: `AssemblyRulesProviding`.
private struct StubRules: AssemblyRulesProviding {
    let version: Int
    func split(forDayCount count: Int) -> [SplitDay] { [] }
    func slotCount(forDurationMinutes minutes: Int) -> Int { 0 }
    func prescription(for role: SlotRole) -> RolePrescription? { nil }
    func setAdjustment(for experience: ExperienceLevel) -> Int { 0 }
    var roleOrder: [SlotRole] { [] }
    var balanceRules: [BalanceRule] { [] }
    var requiredWeeklyPatterns: [MovementPattern] { [] }
    var majorPatterns: [MovementPattern] { [] }
    func targetWeeklyFrequency(forDayCount count: Int) -> Int { 0 }
    var maxShareOfSessionPerPattern: Double { 1 }
    static func bundled(bundle: Bundle) throws -> StubRules { StubRules(version: 4242) }
}

/// Properties the bundled assembly rules must hold, asserted as rules rather
/// than as a restatement of the file's literals.
///
/// A test that reads `sets` out of the JSON and checks it equals the number
/// written in the JSON guards nothing. These check things the data could
/// plausibly get wrong: a missing split, a slot naming a role with no
/// prescription, a rep string no parser accepts, a duration table where a
/// longer session buys fewer exercises, a week that trains a pattern too
/// rarely, and a split whose pull volume trails its press volume.
@Suite("Assembly rules")
struct AssemblyRulesTests {

    private static let dayCounts = 1...6

    private func rules() throws -> AssemblyRules {
        try AssemblyRules.bundled()
    }

    /// Every slot of every day of the split for `count` training days.
    private func weeklySlots(_ rules: AssemblyRules, dayCount count: Int) -> [SessionSlot] {
        rules.split(forDayCount: count).flatMap(\.slots)
    }

    // MARK: - Loading and the seam

    @Test("The bundled rules file is present in the app bundle and decodes")
    func bundledLoads() throws {
        let rules = try rules()
        #expect(rules.version > 0)
        #expect(!rules.split(forDayCount: 3).isEmpty)
    }

    @Test("version is reachable through the protocol, and a fake can vary it")
    func versionIsOnTheSeam() throws {
        func versionSeenThroughSeam(_ provider: any AssemblyRulesProviding) -> Int {
            provider.version
        }
        #expect(versionSeenThroughSeam(StubRules(version: 4242)) == 4242)
        #expect(versionSeenThroughSeam(StubRules(version: 7)) == 7)

        let bundled = try rules()
        #expect(versionSeenThroughSeam(bundled) == bundled.version)
    }

    // MARK: - Splits

    @Test("Every supported day count yields a split with exactly that many days",
          arguments: 1...6)
    func everyDayCountYieldsASplit(count: Int) throws {
        let split = try rules().split(forDayCount: count)
        #expect(split.count == count)
        #expect(split.allSatisfy { !$0.focus.trimmingCharacters(in: .whitespaces).isEmpty })
        #expect(split.allSatisfy { !$0.slots.isEmpty })
    }

    @Test("Day counts outside the table clamp to its ends rather than yielding nothing")
    func dayCountsClamp() throws {
        let rules = try rules()
        #expect(rules.split(forDayCount: 0) == rules.split(forDayCount: 1))
        #expect(rules.split(forDayCount: -3) == rules.split(forDayCount: 1))
        #expect(rules.split(forDayCount: 9) == rules.split(forDayCount: 6))
    }

    @Test("Every slot names a role and a pattern this build recognizes")
    func everySlotNamesARoleAndAPattern() throws {
        let rules = try rules()
        for count in Self.dayCounts {
            for slot in weeklySlots(rules, dayCount: count) {
                #expect(!slot.role.rawValue.isEmpty)
                #expect(!slot.pattern.rawValue.isEmpty)
                #expect(slot.role.isKnown, "Unrecognized role '\(slot.role)' in the \(count)-day split.")
                #expect(slot.pattern.isKnown, "Unrecognized pattern '\(slot.pattern)' in the \(count)-day split.")
            }
        }
    }

    @Test("Every role a slot uses has a prescription")
    func everyUsedRoleIsPrescribed() throws {
        let rules = try rules()
        for count in Self.dayCounts {
            for slot in weeklySlots(rules, dayCount: count) {
                #expect(
                    rules.prescription(for: slot.role) != nil,
                    "Role '\(slot.role)' appears in the \(count)-day split with no sets/reps/rest prescribed."
                )
            }
        }
    }

    @Test("Slots run heaviest first: role demand never increases within a session")
    func slotsAreOrderedByDemand() throws {
        let rules = try rules()
        #expect(!rules.roleOrder.isEmpty)
        #expect(Set(rules.roleOrder).count == rules.roleOrder.count, "roleOrder lists a role twice.")
        let rank = Dictionary(
            rules.roleOrder.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for count in Self.dayCounts {
            for day in rules.split(forDayCount: count) {
                let ranks = day.slots.compactMap { rank[$0.role] }
                #expect(ranks.count == day.slots.count, "A slot in '\(day.focus)' uses a role missing from roleOrder.")
                #expect(ranks == ranks.sorted(), "Slots in '\(day.focus)' are not ordered heaviest first.")
            }
        }
    }

    // MARK: - Prescriptions

    @Test("Every prescription asks for positive sets, positive rest, and a parseable rep range")
    func prescriptionsAreUsable() throws {
        let rules = try rules()
        let roles = Set(Self.dayCounts.flatMap { weeklySlots(rules, dayCount: $0) }.map(\.role))
        #expect(!roles.isEmpty)
        for role in roles {
            let prescription = try #require(rules.prescription(for: role))
            #expect(prescription.sets > 0, "Role '\(role)' prescribes \(prescription.sets) sets.")
            #expect(prescription.restSeconds > 0, "Role '\(role)' prescribes \(prescription.restSeconds)s rest.")

            let range = prescription.repRange
            #expect(!range.isEmpty, "Role '\(role)' rep text '\(prescription.reps)' parsed to no target.")
            #expect(range.lowerBound > 0)
            #expect(range.lowerBound <= range.upperBound)
        }
    }

    @Test("Rep targets are parsed by RepRange rather than by a second parser")
    func repRangesGoThroughRepRange() throws {
        let rules = try rules()
        for role in SlotRole.known {
            guard let prescription = rules.prescription(for: role) else { continue }
            #expect(prescription.repRange == RepRange(prescription.reps))
        }
    }

    @Test("Heavier roles rest longer and use lower reps than lighter ones")
    func prescriptionsTrackRoleDemand() throws {
        let rules = try rules()
        let prescriptions = rules.roleOrder.compactMap { rules.prescription(for: $0) }
        #expect(prescriptions.count == rules.roleOrder.count)
        for (heavier, lighter) in zip(prescriptions, prescriptions.dropFirst()) {
            #expect(heavier.restSeconds >= lighter.restSeconds)
            #expect(heavier.repRange.lowerBound <= lighter.repRange.lowerBound)
        }
    }

    @Test("Experience shifts set volume monotonically, and an unknown level shifts nothing")
    func setAdjustmentsAreMonotonic() throws {
        let rules = try rules()
        let beginner = rules.setAdjustment(for: .beginner)
        let intermediate = rules.setAdjustment(for: .intermediate)
        let advanced = rules.setAdjustment(for: .advanced)
        #expect(beginner <= intermediate)
        #expect(intermediate <= advanced)
        #expect(beginner < advanced, "Experience currently makes no difference to volume.")

        // Every prescribed role must survive the largest downward adjustment.
        for role in SlotRole.known {
            guard let prescription = rules.prescription(for: role) else { continue }
            #expect(prescription.sets + beginner > 0)
        }
    }

    // MARK: - Slot budget by duration

    @Test("A longer session never buys fewer slots, and every budget is positive")
    func slotBudgetIsMonotonic() throws {
        let rules = try rules()
        let counts = stride(from: 10, through: 180, by: 5).map { rules.slotCount(forDurationMinutes: $0) }
        #expect(counts.allSatisfy { $0 > 0 })
        #expect(counts == counts.sorted(), "A longer session was given fewer slots than a shorter one.")
        #expect(Set(counts).count > 1, "The duration table gives every session the same number of slots.")
    }

    @Test("The longest sessions can still be filled by the longest split day")
    func longSessionsAreNotStarvedOfSlots() throws {
        let rules = try rules()
        let longest = Self.dayCounts
            .flatMap { rules.split(forDayCount: $0) }
            .map(\.slots.count)
            .max() ?? 0
        #expect(rules.slotCount(forDurationMinutes: 180) <= longest,
                "A long session asks for more slots than any split day defines, so slots would be left empty.")
    }

    // MARK: - Balance, the reason this app organizes by pattern

    /// The target is a promise about the split as authored — every slot of every
    /// day, which is what a lifter with time for a full session gets. What a
    /// *truncated* week delivers depends on session length too, so it is checked
    /// against real capacity in `SessionSkeletonTests` rather than here.
    @Test("Every split as authored trains each major pattern at least its weekly target",
          arguments: 1...6)
    func everySplitMeetsItsWeeklyFrequencyTarget(count: Int) throws {
        let rules = try rules()
        let target = rules.targetWeeklyFrequency(forDayCount: count)
        #expect(target > 0)
        let slots = weeklySlots(rules, dayCount: count)
        #expect(!rules.majorPatterns.isEmpty)
        for pattern in rules.majorPatterns {
            let occurrences = slots.filter { $0.pattern == pattern }.count
            #expect(
                occurrences >= target,
                "The \(count)-day split trains '\(pattern)' \(occurrences)x per week, below its target of \(target)."
            )
        }
    }

    @Test("The weekly target is twice a week wherever more than one day is trained")
    func twiceWeeklyIsTheStandardWhereItIsAchievable() throws {
        let rules = try rules()
        // Not read back from the file's own target: the programming spec states
        // twice weekly outright, and one training day cannot reach it — six major
        // patterns twice over is twelve slots, more than any single session holds.
        #expect(rules.targetWeeklyFrequency(forDayCount: 1) >= 1)
        for count in 2...6 {
            #expect(
                rules.targetWeeklyFrequency(forDayCount: count) >= 2,
                "The \(count)-day split does not aim at each major pattern twice a week."
            )
        }
    }

    @Test("Every split satisfies its own balance rules", arguments: 1...6)
    func balanceRulesHold(count: Int) throws {
        let rules = try rules()
        #expect(!rules.balanceRules.isEmpty)
        let slots = weeklySlots(rules, dayCount: count)
        for rule in rules.balanceRules {
            let floor = slots.filter { $0.pattern == rule.atLeast }.count
            let ceiling = slots.filter { $0.pattern == rule.comparedTo }.count
            #expect(
                floor >= ceiling,
                "The \(count)-day split prescribes \(ceiling) '\(rule.comparedTo)' against only \(floor) '\(rule.atLeast)'."
            )
        }
    }

    @Test("Every split includes every required weekly pattern", arguments: 1...6)
    func requiredPatternsAppear(count: Int) throws {
        let rules = try rules()
        #expect(!rules.requiredWeeklyPatterns.isEmpty)
        let patterns = Set(weeklySlots(rules, dayCount: count).map(\.pattern))
        for required in rules.requiredWeeklyPatterns {
            #expect(patterns.contains(required), "The \(count)-day split never trains '\(required)'.")
        }
    }

    @Test("No pattern occupies more than its allowed share of a session")
    func noPatternDominatesASession() throws {
        let rules = try rules()
        let share = rules.maxShareOfSessionPerPattern
        #expect(share > 0 && share <= 1)
        for count in Self.dayCounts {
            for day in rules.split(forDayCount: count) {
                var occurrences: [MovementPattern: Int] = [:]
                for slot in day.slots { occurrences[slot.pattern, default: 0] += 1 }
                for (pattern, used) in occurrences {
                    #expect(
                        Double(used) <= share * Double(day.slots.count) + .ulpOfOne,
                        "'\(pattern)' fills \(used) of \(day.slots.count) slots on '\(day.focus)' in the \(count)-day split."
                    )
                }
            }
        }
    }

    // MARK: - Lenient decoding

    private func decode(_ json: String) throws -> AssemblyRules {
        try JSONDecoder().decode(AssemblyRules.self, from: Data(json.utf8))
    }

    private static let minimalRules = """
        {
          "version": 9,
          "splitsByDayCount": { "1": [{ "focus": "Made Up", "slots": ["%@"] }] },
          "slotCountByDurationMinutes": [{ "upTo": 999, "slots": 3 }],
          "roleOrder": ["primary"],
          "byRole": { "primary": { "sets": 3, "reps": "5", "restSeconds": 120 } },
          "setAdjustmentByExperience": { "beginner": -1 },
          "balanceRules": [],
          "requiredWeeklyPatterns": [],
          "majorPatterns": [],
          "targetWeeklyFrequencyByDayCount": { "1": 1 },
          "maxShareOfSessionPerPattern": 1.0
        }
        """

    @Test("An unrecognized role or pattern round-trips intact instead of crashing or being dropped")
    func unknownTaxonomyValuesRoundTrip() throws {
        let json = Self.minimalRules.replacingOccurrences(of: "%@", with: "ballistic:kettlebell swing")
        let rules = try decode(json)
        let slot = try #require(rules.split(forDayCount: 1).first?.slots.first)
        #expect(slot.role == SlotRole(rawValue: "ballistic"))
        #expect(slot.pattern == MovementPattern(rawValue: "kettlebell swing"))
        #expect(!slot.role.isKnown)
        #expect(!slot.pattern.isKnown)
    }

    @Test("Role and pattern text is canonicalized, so casing never splits identity")
    func slotTextIsCanonicalized() throws {
        let json = Self.minimalRules.replacingOccurrences(of: "%@", with: " PRIMARY : Horizontal Press ")
        let rules = try decode(json)
        let slot = try #require(rules.split(forDayCount: 1).first?.slots.first)
        #expect(slot.role == .primary)
        #expect(slot.pattern == .horizontalPress)
    }

    @Test("A slot that is not 'role:pattern' fails loudly rather than decoding to nonsense")
    func malformedSlotThrows() {
        for bad in ["squat", "primary:", ":squat", "  :  "] {
            let json = Self.minimalRules.replacingOccurrences(of: "%@", with: bad)
            #expect(throws: DecodingError.self) { try decode(json) }
        }
    }

    @Test("A day-count key that is not a number fails loudly rather than being skipped")
    func malformedDayCountKeyThrows() {
        let json = Self.minimalRules
            .replacingOccurrences(of: "%@", with: "primary:squat")
            .replacingOccurrences(of: "\"1\": [{ \"focus\"", with: "\"one\": [{ \"focus\"")
        #expect(throws: DecodingError.self) { try decode(json) }
    }

    @Test("An experience level the file says nothing about adjusts nothing")
    func unknownExperienceAdjustsNothing() throws {
        let json = Self.minimalRules.replacingOccurrences(of: "%@", with: "primary:squat")
        let rules = try decode(json)
        #expect(rules.setAdjustment(for: .beginner) == -1)
        #expect(rules.setAdjustment(for: .advanced) == 0)
    }

    @Test("A missing resource throws rather than yielding empty rules")
    func missingResourceThrows() {
        #expect(throws: (any Error).self) {
            try AssemblyRules.bundled(bundle: Bundle(for: BundleMarker.self))
        }
    }
}

/// Anchors a bundle that contains no `assembly-rules.json`, so the missing-resource
/// path can be exercised. Depends on: Foundation.
private final class BundleMarker {}
