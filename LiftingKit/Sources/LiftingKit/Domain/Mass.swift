import Foundation

/// The unit a weight was recorded in.
///
/// Raw values are the abbreviations shown in the UI and stored in the
/// database. Depends on: Foundation only.
public enum MassUnit: String, Codable, Hashable, Sendable, CaseIterable {
    case kilograms = "kg"
    case pounds = "lb"
}

/// A weight that always knows its unit.
///
/// Construct one with the value the lifter actually entered, in the unit they
/// entered it. `Mass` never canonicalizes on storage: someone who logged
/// 135 lb sees 135 forever, not 61.23 kg rendered back as 134.99. Use
/// `kilograms` when comparing across units — charts, estimated 1RM,
/// progression — so conversion happens at the point of comparison instead.
///
/// Note that `==` is exact on representation, so 100 lb does not equal its own
/// conversion to kilograms. Compare `kilograms` when you mean physical
/// equivalence.
///
/// Depends on: Foundation only.
public struct Mass: Codable, Hashable, Sendable {

    /// Exact by definition: one pound is 0.45359237 kg. Internal — callers read
    /// `kilograms` or `pounds` rather than doing the arithmetic themselves.
    static let kilogramsPerPound = 0.45359237

    /// The number as entered, in `unit`.
    public let value: Double
    public let unit: MassUnit

    public init(value: Double, unit: MassUnit) {
        self.value = value
        self.unit = unit
    }

    public var kilograms: Double {
        switch unit {
        case .kilograms: value
        case .pounds: value * Self.kilogramsPerPound
        }
    }

    public var pounds: Double {
        switch unit {
        case .pounds: value
        case .kilograms: value / Self.kilogramsPerPound
        }
    }

    /// The same physical weight expressed in another unit.
    public func converted(to target: MassUnit) -> Mass {
        guard target != unit else { return self }
        return switch target {
        case .kilograms: Mass(value: kilograms, unit: .kilograms)
        case .pounds: Mass(value: pounds, unit: .pounds)
        }
    }

    /// Snapped to the nearest usable increment, for plate math and to absorb
    /// floating-point drift from conversion.
    public func rounded(toNearest increment: Double) -> Mass {
        guard increment > 0 else { return self }
        return Mass(value: (value / increment).rounded() * increment, unit: unit)
    }
}
