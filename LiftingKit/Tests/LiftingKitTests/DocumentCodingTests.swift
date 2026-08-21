import Foundation
import Testing
@testable import LiftingKit

/// That the three formats crossing the shared folder agree about how they are
/// written.
///
/// Each used to build its own encoder and decoder with identical bodies, which
/// is not the same as being guaranteed identical: a date strategy changed on one
/// and not the others would stay invisible until the phone wrote a snapshot the
/// server could not read, and that failure looks like a missing file rather than
/// a mismatched one. They share `DocumentCoding` now, and this is what keeps
/// them sharing it.
@Suite("Document coding")
struct DocumentCodingTests {

    /// A date on a second boundary, since ISO 8601 carries whole seconds.
    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)

    private struct Stamped: Codable, Equatable {
        let at: Date
        let path: String
    }

    @Test("Every format writes dates the same way, and it is ISO 8601")
    func datesAgree() throws {
        let value = Stamped(at: Self.instant, path: "a/b")
        let written = [
            try PlanDocument.makeEncoder().encode(value),
            try TrainingSnapshot.makeEncoder().encode(value),
            try PlanDocument.makeEncoder().encode(value),
        ]

        #expect(Set(written).count == 1, "one format writing a date differently is the bug")
        let text = String(decoding: written[0], as: UTF8.self)
        #expect(text.contains("2023-11-14T22:13:20Z"))
    }

    @Test("Every format reads what any of them wrote")
    func decodersAgree() throws {
        let value = Stamped(at: Self.instant, path: "a/b")
        let data = try TrainingSnapshot.makeEncoder().encode(value)

        for decoder in [
            PlanDocument.makeDecoder(), TrainingSnapshot.makeDecoder(),
            PlanDocument.makeDecoder(),
        ] {
            #expect(try decoder.decode(Stamped.self, from: data) == value)
        }
    }

    @Test("A document is written for a person to read: sorted, spaced, unescaped")
    func shapeIsReadable() throws {
        let text = String(
            decoding: try PlanDocument.makeEncoder().encode(Stamped(at: Self.instant, path: "a/b")),
            as: UTF8.self)

        // Sorted keys and indentation are what make a diff of two snapshots
        // legible; the unescaped slash is what keeps a path looking like a path.
        #expect(text.contains("\n"))
        #expect(text.range(of: "\"at\"")!.lowerBound < text.range(of: "\"path\"")!.lowerBound)
        #expect(text.contains("a/b"))
        #expect(text.contains("a\\/b") == false)
    }

    @Test("A bare decoder cannot read what these write, which is why nothing builds one")
    func aBareDecoderFails() throws {
        let data = try PlanDocument.makeEncoder().encode(Stamped(at: Self.instant, path: "a"))

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Stamped.self, from: data)
        }
    }
}
