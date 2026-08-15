import Foundation

/// Read access to the programming rules that shape a generated week.
///
/// Depend on this rather than `AssemblyRules` so a service can be handed a
/// fixture — a two-day split, a single role — instead of the whole bundled
/// file.
///
/// `version` is part of the seam deliberately: a service that assembles a plan
/// must be able to record which generation of the rules produced it, and a fake
/// must be able to vary that number. Omitting `version` from
/// `ExerciseCatalogProviding` was the direct cause of exactly that defect.
/// Depends on: `SplitDay`, `SlotRole`, `RolePrescription`, `BalanceRule`,
/// `MovementPattern`, `ExperienceLevel`.
protocol AssemblyRulesProviding: Sendable {

    /// Which generation of `assembly-rules.json` these rules came from.
    var version: Int { get }

    /// The split for a lifter training `count` days a week, clamped to the
    /// range the file defines. Empty only if the file defines no splits.
    func split(forDayCount count: Int) -> [SplitDay]

    /// How many slots a session of this length is worth.
    func slotCount(forDurationMinutes minutes: Int) -> Int

    /// Sets, reps, and rest for a role, or `nil` if the file prescribes none.
    func prescription(for role: SlotRole) -> RolePrescription?

    /// How many sets to add or remove for a lifter of this experience. Zero
    /// for a level the file says nothing about.
    func setAdjustment(for experience: ExperienceLevel) -> Int

    /// Roles from most to least neurologically demanding — the order slots run in.
    var roleOrder: [SlotRole] { get }

    /// The patterns a balanced week must not let drift apart.
    var balanceRules: [BalanceRule] { get }

    /// Patterns that must appear in every training week.
    var requiredWeeklyPatterns: [MovementPattern] { get }

    /// The patterns whose weekly frequency is worth guaranteeing.
    var majorPatterns: [MovementPattern] { get }

    /// How often each major pattern must be trained by a lifter training
    /// `count` days a week.
    func minimumWeeklyFrequency(forDayCount count: Int) -> Int

    /// The largest fraction of one session's slots a single pattern may fill.
    var maxShareOfSessionPerPattern: Double { get }

    /// Loads the rules that ship with `bundle`.
    static func bundled(bundle: Bundle) throws -> Self
}

/// The bundled programming rules: which split for how many training days, how
/// many slots for how long a session, and what sets, reps, and rest each slot
/// role is worth.
///
/// Build one with `bundled()` at app start and pass it down. This is immutable
/// reference data of the same kind as the exercise catalog — it ships with the
/// app, is never written at runtime, and is therefore not a SwiftData model.
/// Every number in it is a training opinion, which is why they live in
/// `assembly-rules.json` rather than in a `switch` inside plan generation.
///
/// `version` identifies which generation of that file this is, so a plan can
/// record the rules that built it and a later correction can be detected rather
/// than silently reinterpreting work already logged.
///
/// Depends on: `MovementPattern`, `RepRange`, and `ExperienceLevel` from
/// Domain. No persistence, no UI.
struct AssemblyRules: AssemblyRulesProviding, Decodable {

    let version: Int
    let roleOrder: [SlotRole]
    let balanceRules: [BalanceRule]
    let requiredWeeklyPatterns: [MovementPattern]
    let majorPatterns: [MovementPattern]
    let maxShareOfSessionPerPattern: Double

    private let splitsByDayCount: [Int: [SplitDay]]
    private let dayCountBounds: ClosedRange<Int>?
    private let slotBudgets: [SlotBudget]
    private let prescriptionsByRole: [SlotRole: RolePrescription]
    private let setAdjustments: [String: Int]
    private let minimumsByDayCount: [Int: Int]
    private let minimumBounds: ClosedRange<Int>?

    private enum CodingKeys: String, CodingKey {
        case version, roleOrder, majorPatterns, minimumWeeklyFrequencyByDayCount
        case splitsByDayCount, slotCountByDurationMinutes, byRole
        case setAdjustmentByExperience, balanceRules, requiredWeeklyPatterns
        case maxShareOfSessionPerPattern
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        roleOrder = try container.decode([SlotRole].self, forKey: .roleOrder)
        majorPatterns = try container.decode([MovementPattern].self, forKey: .majorPatterns)
        balanceRules = try container.decode([BalanceRule].self, forKey: .balanceRules)
        requiredWeeklyPatterns = try container.decode([MovementPattern].self, forKey: .requiredWeeklyPatterns)
        maxShareOfSessionPerPattern = try container.decode(Double.self, forKey: .maxShareOfSessionPerPattern)

        slotBudgets = try container
            .decode([SlotBudget].self, forKey: .slotCountByDurationMinutes)
            .sorted { $0.upTo < $1.upTo }

        let splits = try container.decode([String: [SplitDay]].self, forKey: .splitsByDayCount)
        splitsByDayCount = try Self.keyedByDayCount(splits, at: container, forKey: .splitsByDayCount)
        dayCountBounds = Self.bounds(of: splitsByDayCount.keys)

        let minimums = try container.decode([String: Int].self, forKey: .minimumWeeklyFrequencyByDayCount)
        minimumsByDayCount = try Self.keyedByDayCount(minimums, at: container, forKey: .minimumWeeklyFrequencyByDayCount)
        minimumBounds = Self.bounds(of: minimumsByDayCount.keys)

        let byRole = try container.decode([String: RolePrescription].self, forKey: .byRole)
        prescriptionsByRole = Dictionary(
            byRole.map { (SlotRole(rawValue: $0.key), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )

        let adjustments = try container.decode([String: Int].self, forKey: .setAdjustmentByExperience)
        setAdjustments = Dictionary(
            adjustments.map { (Self.canonical($0.key), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Trimmed and lowercased, matching how the taxonomies canonicalize, so an
    /// `ExperienceLevel` written `"Beginner"` in code finds `"beginner"` in the
    /// file.
    private static func canonical(_ raw: String) -> String {
        SlotRole.canonicalized(raw)
    }

    /// Re-keys a `{"3": …}` object by integer day count. A key that is not a
    /// number is malformed structure, not an unknown taxonomy value, so it
    /// throws rather than being skipped — a silently dropped split would leave
    /// a lifter with no training days at all.
    private static func keyedByDayCount<Value>(
        _ source: [String: Value],
        at container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> [Int: Value] {
        var result: [Int: Value] = [:]
        for (rawKey, value) in source {
            guard let dayCount = Int(rawKey.trimmingCharacters(in: .whitespaces)) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: container,
                    debugDescription: "'\(rawKey)' is not a number of training days."
                )
            }
            result[dayCount] = value
        }
        return result
    }

    private static func bounds(of keys: some Collection<Int>) -> ClosedRange<Int>? {
        guard let low = keys.min(), let high = keys.max() else { return nil }
        return low...high
    }

    /// Loads `assembly-rules.json` from the app bundle.
    ///
    /// Throws `CatalogError.resourceMissing` if the resource is absent and a
    /// `DecodingError` if it is malformed. Both are programmer errors that must
    /// fail loudly rather than yield rules that generate nothing.
    static func bundled(bundle: Bundle = .main) throws -> AssemblyRules {
        guard let url = bundle.url(forResource: "assembly-rules", withExtension: "json") else {
            throw CatalogError.resourceMissing("assembly-rules.json")
        }
        return try JSONDecoder().decode(AssemblyRules.self, from: try Data(contentsOf: url))
    }

    func split(forDayCount count: Int) -> [SplitDay] {
        guard let bounds = dayCountBounds else { return [] }
        return splitsByDayCount[bounds.clamping(count)] ?? []
    }

    func slotCount(forDurationMinutes minutes: Int) -> Int {
        slotBudgets.first { minutes <= $0.upTo }?.slots ?? slotBudgets.last?.slots ?? 0
    }

    func prescription(for role: SlotRole) -> RolePrescription? {
        prescriptionsByRole[role]
    }

    func setAdjustment(for experience: ExperienceLevel) -> Int {
        setAdjustments[Self.canonical(experience.rawValue)] ?? 0
    }

    func minimumWeeklyFrequency(forDayCount count: Int) -> Int {
        guard let bounds = minimumBounds else { return 0 }
        return minimumsByDayCount[bounds.clamping(count)] ?? 0
    }
}

private extension ClosedRange where Bound == Int {
    /// Pins a value inside the range, so a lifter asking for more or fewer
    /// training days than the file describes still gets the nearest split.
    func clamping(_ value: Int) -> Int {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
