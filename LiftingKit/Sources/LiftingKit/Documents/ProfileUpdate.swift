import Foundation

/// A change to the lifter's standing facts, as Claude learned them in
/// conversation.
///
/// This travels the same way a `PlanDocument` does — the MCP server writes one
/// into the shared folder, the app notices it and applies it — and it is the
/// only way facts about the lifter enter the app, because the app asks him
/// nothing. Encode it with `makeEncoder()` and decode it with `makeDecoder()`
/// so the Mac and the phone cannot disagree about how a date is written.
///
/// **It is a patch, not a record.** A field it does not mention is left exactly
/// as it was; that is what lets Claude record one thing it just learned ("he has
/// a rack now") without restating, and possibly clobbering, everything else. A
/// field it sets to `null` returns to not-known, which is how a fact recorded in
/// error is taken back rather than merely overwritten with another guess.
///
/// `id` is the update's stable identity: an update already applied is applied
/// once, so a document left sitting in the folder does not keep re-imposing
/// itself over a later change.
///
/// Depends on: `StatedValue`, `MassUnit`, `ExperienceLevel`, `Equipment`,
/// `MovementPattern`, `ExerciseID`, and `Weekday`. Pure value types by design —
/// the macOS server writes these and must never link SwiftData, so the mapping
/// into the store lives in the app.
public struct ProfileUpdate: Codable, Hashable, Sendable, Identifiable {

    /// The format version this build writes. Bump it when a reader would need
    /// to behave differently, not for an additive field.
    public static let currentVersion = 1

    /// The format version of this document, as written.
    public let version: Int
    /// The update's stable identity. Applying the same identity twice changes
    /// nothing the second time.
    public let id: UUID
    /// When the update was written. The app records when it *arrived*
    /// separately, since an update can be written before it is applied.
    public let generatedAt: Date

    /// How the app renders weights. Not a training fact — it is the one thing
    /// the lifter can still set for himself in Settings.
    public let displayUnit: StatedValue<MassUnit>
    public let experience: StatedValue<ExperienceLevel>
    public let equipmentAccess: StatedValue<Equipment>
    /// What he is training for, in his words. Cleared to no stated goal.
    public let goal: StatedValue<String>
    /// Injuries and limitations, in his words. Cleared to no stated constraint.
    public let constraints: StatedValue<String>
    /// Movement patterns to keep out of his training. Replaces the stored list
    /// wholesale rather than adding to it — a patch that could only add could
    /// never record a shoulder that healed.
    public let avoidedPatterns: StatedValue<[MovementPattern]>
    /// Specific exercises to keep out of his training. Replaces wholesale, for
    /// the same reason.
    public let avoidedExercises: StatedValue<[ExerciseID]>
    /// The days he says he wants to train. Replaces wholesale.
    public let preferredWeekdays: StatedValue<[Weekday]>
    /// How long he wants a session to run.
    public let preferredDurationMinutes: StatedValue<Int>

    public init(
        version: Int = ProfileUpdate.currentVersion,
        id: UUID,
        generatedAt: Date,
        displayUnit: StatedValue<MassUnit> = .unchanged,
        experience: StatedValue<ExperienceLevel> = .unchanged,
        equipmentAccess: StatedValue<Equipment> = .unchanged,
        goal: StatedValue<String> = .unchanged,
        constraints: StatedValue<String> = .unchanged,
        avoidedPatterns: StatedValue<[MovementPattern]> = .unchanged,
        avoidedExercises: StatedValue<[ExerciseID]> = .unchanged,
        preferredWeekdays: StatedValue<[Weekday]> = .unchanged,
        preferredDurationMinutes: StatedValue<Int> = .unchanged
    ) {
        self.version = version
        self.id = id
        self.generatedAt = generatedAt
        self.displayUnit = displayUnit
        self.experience = experience
        self.equipmentAccess = equipmentAccess
        self.goal = goal
        self.constraints = constraints
        self.avoidedPatterns = avoidedPatterns
        self.avoidedExercises = avoidedExercises
        self.preferredWeekdays = preferredWeekdays
        self.preferredDurationMinutes = preferredDurationMinutes
    }

    /// Whether this update would change nothing at all. An empty patch is not
    /// an error — it is a caller that learned nothing — but it is worth being
    /// able to say so rather than reporting a write that meant nothing.
    public var statesNothing: Bool {
        displayUnit.isUnchanged && experience.isUnchanged && equipmentAccess.isUnchanged
            && goal.isUnchanged && constraints.isUnchanged && avoidedPatterns.isUnchanged
            && avoidedExercises.isUnchanged && preferredWeekdays.isUnchanged
            && preferredDurationMinutes.isUnchanged
    }

    /// This update laid over one that has not been applied yet.
    ///
    /// The folder holds one update at a time, so a second one written before
    /// the phone has taken the first in would otherwise replace it and lose
    /// what it said. Fold instead: this update's fields win where it states
    /// anything, and the earlier one's stand where it does not. The result
    /// keeps *this* update's identity and timestamp, because it is the document
    /// that will actually be written.
    ///
    /// Only correct against an update that is genuinely still waiting. Folding
    /// in one the phone has already applied would re-impose facts the lifter
    /// may have changed since.
    public func superseding(_ earlier: ProfileUpdate) -> ProfileUpdate {
        ProfileUpdate(
            version: version,
            id: id,
            generatedAt: generatedAt,
            displayUnit: displayUnit.superseding(earlier.displayUnit),
            experience: experience.superseding(earlier.experience),
            equipmentAccess: equipmentAccess.superseding(earlier.equipmentAccess),
            goal: goal.superseding(earlier.goal),
            constraints: constraints.superseding(earlier.constraints),
            avoidedPatterns: avoidedPatterns.superseding(earlier.avoidedPatterns),
            avoidedExercises: avoidedExercises.superseding(earlier.avoidedExercises),
            preferredWeekdays: preferredWeekdays.superseding(earlier.preferredWeekdays),
            preferredDurationMinutes: preferredDurationMinutes.superseding(
                earlier.preferredDurationMinutes)
        )
    }

    /// Spelled out rather than synthesized: this type writes both halves of
    /// `Codable` by hand, so nothing generates these.
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, id, generatedAt
        case displayUnit, experience, equipmentAccess, goal, constraints
        case avoidedPatterns, avoidedExercises, preferredWeekdays, preferredDurationMinutes
    }

    /// The facts an update may state, as they are written on the wire.
    ///
    /// Public because the MCP server takes these same names as its tool
    /// arguments and must refuse a key this document could not hold. Read from
    /// the coding keys rather than retyped, so a fact added here cannot be one
    /// the server keeps rejecting.
    public static let statedKeys: Set<String> = Set(
        CodingKeys.allCases.map(\.stringValue)
    ).subtracting(["version", "id", "generatedAt"])

    /// Every key the document itself may carry: the facts, plus the three
    /// things that make it a document.
    private static let acceptedKeys: Set<String> =
        Set(CodingKeys.allCases.map(\.stringValue))

    /// Only the three facts about the document itself are required. Every
    /// standing fact is three-way: absent, stated, or explicitly `null`.
    ///
    /// A key this format does not have is refused rather than dropped — an
    /// update reported as recorded while a fact in it was quietly discarded is
    /// worse than one that was refused and could be sent again. A document from
    /// a later format is refused as such, before any of its keys are held
    /// against it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        guard version <= Self.currentVersion else {
            throw DocumentRefusal.laterVersion(version, understood: Self.currentVersion)
        }
        try decoder.refuseUnknownKeys(besides: Self.acceptedKeys)
        id = try container.decode(UUID.self, forKey: .id)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        displayUnit = try container.decodeStated(MassUnit.self, forKey: .displayUnit)
        experience = try container.decodeStated(ExperienceLevel.self, forKey: .experience)
        equipmentAccess = try container.decodeStated(Equipment.self, forKey: .equipmentAccess)
        goal = try container.decodeStated(String.self, forKey: .goal)
        constraints = try container.decodeStated(String.self, forKey: .constraints)
        avoidedPatterns = try container.decodeStated(
            [MovementPattern].self, forKey: .avoidedPatterns)
        avoidedExercises = try container.decodeStated(
            [ExerciseID].self, forKey: .avoidedExercises)
        preferredWeekdays = try container.decodeStated(
            [Weekday].self, forKey: .preferredWeekdays)
        preferredDurationMinutes = try container.decodeStated(
            Int.self, forKey: .preferredDurationMinutes)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(id, forKey: .id)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encodeStated(displayUnit, forKey: .displayUnit)
        try container.encodeStated(experience, forKey: .experience)
        try container.encodeStated(equipmentAccess, forKey: .equipmentAccess)
        try container.encodeStated(goal, forKey: .goal)
        try container.encodeStated(constraints, forKey: .constraints)
        try container.encodeStated(avoidedPatterns, forKey: .avoidedPatterns)
        try container.encodeStated(avoidedExercises, forKey: .avoidedExercises)
        try container.encodeStated(preferredWeekdays, forKey: .preferredWeekdays)
        try container.encodeStated(preferredDurationMinutes, forKey: .preferredDurationMinutes)
    }

    /// The encoder both clients use. ISO 8601 dates and sorted keys, so an
    /// update is diffable and a Mac and a phone cannot disagree about an
    /// instant.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// The matching decoder. Use it rather than a bare `JSONDecoder`, whose
    /// default date strategy would reject everything `makeEncoder()` writes.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension KeyedDecodingContainer {

    /// The three-way reading `StatedValue` needs, which no `decodeIfPresent`
    /// can give: that one answers `nil` for a missing key and for an explicit
    /// `null` alike, and the whole point here is telling those apart.
    fileprivate func decodeStated<Value: Decodable & Hashable & Sendable>(
        _ type: Value.Type, forKey key: Key
    ) throws -> StatedValue<Value> {
        guard contains(key) else { return .unchanged }
        if try decodeNil(forKey: key) { return .unstated }
        return .stated(try decode(Value.self, forKey: key))
    }
}

extension KeyedEncodingContainer {

    /// The mirror: `unchanged` writes no key at all, `unstated` writes `null`.
    fileprivate mutating func encodeStated<Value: Encodable & Hashable & Sendable>(
        _ stated: StatedValue<Value>, forKey key: Key
    ) throws {
        switch stated {
        case .unchanged: break
        case .stated(let value): try encode(value, forKey: key)
        case .unstated: try encodeNil(forKey: key)
        }
    }
}
