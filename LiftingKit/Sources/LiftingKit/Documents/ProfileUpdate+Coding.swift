import Foundation

// How a `ProfileUpdate` is written and read.
//
// Kept apart from the type itself because it is a different job: the type says
// what an update is, this says what survives the trip. Both halves of `Codable`
// are written by hand for one reason — the format has to tell an absent key, an
// explicit `null`, and a stated value apart, and no synthesized decoder can.

extension ProfileUpdate {

    /// Spelled out rather than synthesized: this type writes both halves of
    /// `Codable` by hand, so nothing generates these.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case version, id, generatedAt
        case displayUnit, experience, equipment, goal, constraints
        case avoidedPatterns, avoidedExercises, preferredDurationMinutes
        case bodyweight, baselines
    }

    /// The key a version 1 document stated its gym in. Read, never written.
    private enum LegacyCodingKeys: String, CodingKey {
        case equipmentAccess
        /// Retired on 2026-08-20. Which days he trains was carried for a reader
        /// and computed with by nothing: the app hands him the session and when
        /// he does it is his business. A document still naming it reads — an
        /// update written before it went is not a broken update — and the value
        /// is ignored, because there is nowhere left for it to mean anything.
        case preferredWeekdays
    }

    /// The facts an update may state, as they are written on the wire.
    ///
    /// Public because the MCP server takes these same names as its tool
    /// arguments and must refuse a key this document could not hold. Read from
    /// the coding keys rather than retyped, so a fact added here cannot be one
    /// the server keeps rejecting. The retired `equipmentAccess` is not among
    /// them: a document may still be read with it, but a caller writing one
    /// today is told, by name, that `equipment` is where a gym goes now.
    public static var statedKeys: Set<String> {
        Set(CodingKeys.allCases.map(\.stringValue)).subtracting(["version", "id", "generatedAt"])
    }

    /// The stated keys whose absence cannot be read, and why.
    ///
    /// Every other fact is three-way — absent, stated, or explicitly none — so
    /// an empty one means nobody has said. These three are not. `displayUnit`
    /// always has a value and is about how a number is drawn rather than about
    /// the lifter; the two avoided lists are plain lists with no absent state,
    /// so an empty one cannot be told from a lifter who avoids nothing. Calling
    /// any of them *not yet said* would assert something the record does not
    /// know.
    ///
    /// **It lives here because two surveys read it.** The phone's account page
    /// and the server's `unstated_facts` each report what nobody has stated, and
    /// each is checked against `statedKeys` less this set. Two copies of the
    /// list would let the two reports disagree about a fact while both passing
    /// their own tests, which is the one failure a survey of absences must not
    /// have.
    public static let unsurveyableKeys: Set<String> = [
        "displayUnit", "avoidedPatterns", "avoidedExercises",
    ]

    /// Every key a document itself may carry: the facts, the three things that
    /// make it a document, and the one key an older format used.
    private static var acceptedKeys: Set<String> {
        Set(CodingKeys.allCases.map(\.stringValue)).union([
            LegacyCodingKeys.equipmentAccess.stringValue,
            LegacyCodingKeys.preferredWeekdays.stringValue,
        ])
    }

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
        let version = try container.decode(Int.self, forKey: .version)
        guard version <= Self.currentVersion else {
            throw DocumentRefusal.laterVersion(version, understood: Self.currentVersion)
        }
        try decoder.refuseUnknownKeys(besides: Self.acceptedKeys)

        self.init(
            version: version,
            id: try container.decode(UUID.self, forKey: .id),
            generatedAt: try container.decode(Date.self, forKey: .generatedAt),
            displayUnit: try container.decodeStated(MassUnit.self, forKey: .displayUnit),
            experience: try container.decodeStated(ExperienceLevel.self, forKey: .experience),
            equipment: try Self.equipment(from: decoder, container),
            goal: try container.decodeStated(String.self, forKey: .goal),
            constraints: try container.decodeStated(String.self, forKey: .constraints),
            avoidedPatterns: try container.decodeStated(
                [MovementPattern].self, forKey: .avoidedPatterns),
            avoidedExercises: try container.decodeStated(
                [ExerciseID].self, forKey: .avoidedExercises),
            preferredDurationMinutes: try container.decodeStated(
                Int.self, forKey: .preferredDurationMinutes),
            bodyweight: try container.decodeSeries(
                [BodyweightReading].self, forKey: .bodyweight, as: .bodyweight),
            baselines: try container.decodeSeries(
                [BaselineStatement].self, forKey: .baselines, as: .baselines)
        )
    }

    /// What the lifter owns, however the document said it.
    ///
    /// A version 1 document said it as a coarse tier under `equipmentAccess`,
    /// which is read as the equipment that tier stood for — and a tier this
    /// build does not recognize is carried as an equipment type of its own
    /// rather than rejecting a document that was recording a true fact. Stating
    /// both keys is refused rather than resolved: picking one would drop the
    /// other, and there is no telling which the writer meant.
    private static func equipment(
        from decoder: any Decoder, _ container: KeyedDecodingContainer<CodingKeys>
    ) throws -> StatedValue<[EquipmentType]> {
        let owned = try container.decodeStated([EquipmentType].self, forKey: .equipment)
        let legacy = try Self.legacyEquipment(from: decoder)
        guard owned.isUnchanged || legacy.isUnchanged else {
            throw DocumentRefusal.contradiction(
                "This update states both 'equipment' and the retired 'equipmentAccess', and only "
                    + "one of them can be what he owns. Nothing was taken in. Send 'equipment' — "
                    + "the list of what he actually has, which is what everything filters on.")
        }
        return owned.isUnchanged ? legacy : owned
    }

    private static func legacyEquipment(
        from decoder: any Decoder
    ) throws -> StatedValue<[EquipmentType]> {
        let container = try decoder.container(keyedBy: LegacyCodingKeys.self)
        guard container.contains(.equipmentAccess) else { return .unchanged }
        if try container.decodeNil(forKey: .equipmentAccess) { return .unstated }
        let stated = try container.decode(String.self, forKey: .equipmentAccess)
        guard let tier = Equipment(rawValue: stated) else {
            // Not a tier this build offers. It is still something the writer
            // said the lifter has, so it is carried as an equipment type: an
            // unrecognized value round-trips, it does not reject a document.
            return .stated([EquipmentType(rawValue: stated)])
        }
        return .stated(EquipmentAccess.permitted(for: tier).sorted { $0.rawValue < $1.rawValue })
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(id, forKey: .id)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encodeStated(displayUnit, forKey: .displayUnit)
        try container.encodeStated(experience, forKey: .experience)
        try container.encodeStated(equipment, forKey: .equipment)
        try container.encodeStated(goal, forKey: .goal)
        try container.encodeStated(constraints, forKey: .constraints)
        try container.encodeStated(avoidedPatterns, forKey: .avoidedPatterns)
        try container.encodeStated(avoidedExercises, forKey: .avoidedExercises)
        try container.encodeStated(preferredDurationMinutes, forKey: .preferredDurationMinutes)
        if !bodyweight.isEmpty { try container.encode(bodyweight, forKey: .bodyweight) }
        if !baselines.isEmpty { try container.encode(baselines, forKey: .baselines) }
    }

    /// The encoder both clients use. ISO 8601 dates and sorted keys, so an
    /// update is diffable and a Mac and a phone cannot disagree about an
    /// instant.
    public static func makeEncoder() -> JSONEncoder { DocumentCoding.makeEncoder() }

    /// The matching decoder. Use it rather than a bare `JSONDecoder`, whose
    /// default date strategy would reject everything `makeEncoder()` writes.
    /// Both are `DocumentCoding`'s, so the three formats cannot drift apart.
    public static func makeDecoder() -> JSONDecoder { DocumentCoding.makeDecoder() }
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

    /// A series of records: absent is no records, and an explicit `null` is
    /// refused with the reason.
    ///
    /// A series is not a value that can be taken back by nulling it. Read as
    /// "no readings" a `null` would report success while the entry the writer
    /// meant to correct stayed exactly as it was; read as "forget the series" it
    /// would destroy a history nobody asked it to. Neither can be inferred, so
    /// the document says which it meant by stating the record again.
    ///
    /// The refusal is built by `DocumentRefusal.nulledSeries(_:)`, which the MCP
    /// server's argument reader throws as well, so the two clients cannot answer
    /// this differently.
    fileprivate func decodeSeries<Record: Decodable>(
        _ type: [Record].Type, forKey key: Key, as series: ProfileSeries
    ) throws -> [Record] {
        guard contains(key) else { return [] }
        guard try !decodeNil(forKey: key) else {
            throw DocumentRefusal.nulledSeries(series)
        }
        return try decode([Record].self, forKey: key)
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
