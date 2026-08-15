import Foundation
import LiftingKit

extension ToolRunner {

    /// Writes `plan.json` into the shared folder and returns the plan exactly
    /// as it was written.
    ///
    /// **One thing is checked and nothing at all is changed.** Every
    /// `exerciseID` must exist in the catalog, because training history is
    /// keyed on exercise identity and an unknown key would split one lift's
    /// history into two series that can never be rejoined. A bad ID fails the
    /// whole call with that ID named and writes nothing — the same contract
    /// `PlanImporter` enforces on the phone, moved forward to the moment the
    /// plan is written so Claude learns about it immediately rather than after
    /// a silent no-op on the device.
    ///
    /// Beyond that check, every value is recorded verbatim. No set count is
    /// capped, no rest clamped, no empty rep range filled, no load seeded. A
    /// prescription that states no rest is written with none.
    ///
    /// The document's identity, catalog version and timestamp are supplied
    /// here rather than asked for: they are facts about the write, and this is
    /// the code that knows them. `id` is fresh on every call, so two plans
    /// written in a row are two plans on the phone rather than one silently
    /// re-imported.
    func writePlan(_ arguments: JSONValue) -> ToolOutcome {
        guard let days = arguments["days"]?.arrayValue else {
            return .failure(
                "write_plan needs a 'days' array — the training days of the block. A day with "
                    + "no exercises is a rest day and is fine; leaving 'days' out entirely is "
                    + "not a plan, so nothing was written.")
        }

        var normalizedDays: [JSONValue] = []
        for day in days {
            switch Self.normalizeWeekday(in: day) {
            case .normalized(let normalized): normalizedDays.append(normalized)
            case .refused(let message): return .failure(message)
            }
        }

        var fields = arguments.objectValue ?? [:]
        fields["days"] = .array(normalizedDays)
        fields["version"] = .integer(PlanDocument.currentVersion)
        fields["id"] = .string(UUID().uuidString)
        fields["catalogVersion"] = .integer(catalog.version)
        fields["generatedAt"] = .date(now())

        let document: PlanDocument
        do {
            document = try JSONValue.object(fields)
                .decoded(as: PlanDocument.self, using: PlanDocument.makeDecoder())
        } catch {
            return .failure(Self.describe(decodingFailure: error))
        }

        if let unknown = Self.firstUnknownExercise(in: document, using: catalog) {
            return .failure(
                "This plan prescribes '\(unknown.rawValue)', which is not in the exercise "
                    + "catalog (version \(catalog.version)). Nothing was written. Find the real "
                    + "ID with \(ToolCatalog.listExercises) and call write_plan again — history "
                    + "is keyed on exercise identity, so an invented ID would fragment a lift's "
                    + "history irreparably.")
        }

        do {
            try documents.writePlan(document)
        } catch {
            return .failure(
                "The plan could not be written to \(documents.planLocation): "
                    + "\(error.localizedDescription) Nothing was saved, so the lifter's phone "
                    + "will not see this plan.")
        }

        return .report([
            "writtenTo": .string(documents.planLocation),
            "dayCount": .integer(document.days.count),
            "exerciseCount": .integer(document.days.reduce(0) { $0 + $1.exercises.count }),
            "note": "Written. The app imports it the next time it is opened or comes forward.",
            "plan": Self.reported(document),
        ])
    }

    /// The first ID the catalog does not have, in document order, so the error
    /// names the one to fix rather than an arbitrary one.
    private static func firstUnknownExercise(
        in document: PlanDocument, using catalog: any ExerciseCatalogProviding
    ) -> ExerciseID? {
        for day in document.days {
            for exercise in day.exercises where catalog.exercise(id: exercise.exerciseID) == nil {
                return exercise.exerciseID
            }
        }
        return nil
    }

    // MARK: - Weekdays, however they were written

    /// Turns a day's `weekday` into the number `Weekday` decodes from.
    ///
    /// `Weekday` is stored as `Calendar`'s 1-based numbering, which is exact
    /// and easy to get wrong from memory, so a name is accepted too. This
    /// translates at the edge rather than loosening the shared type — the phone
    /// and the server must keep decoding the document identically.
    private static func normalizeWeekday(in day: JSONValue) -> WeekdayNormalization {
        var fields = day.objectValue ?? [:]
        guard let raw = day["weekday"] else {
            return .refused(
                "Every day needs a 'weekday', written as a name ('monday') or as Calendar's "
                    + "numbering where 1 is Sunday and 7 is Saturday. Nothing was written.")
        }
        if let number = raw.intValue {
            guard Weekday(rawValue: number) != nil else {
                return .refused(
                    "'\(number)' is not a weekday. Use 1 for Sunday through 7 for Saturday, or "
                        + "write the name. Nothing was written.")
            }
            fields["weekday"] = .integer(number)
            return .normalized(.object(fields))
        }
        guard let name = raw.stringValue, let weekday = Weekday.named(name) else {
            return .refused(
                "'\(raw.stringValue ?? "that value")' is not a weekday. Write a name such as "
                    + "'monday', or Calendar's numbering where 1 is Sunday and 7 is Saturday. "
                    + "Nothing was written.")
        }
        fields["weekday"] = .integer(weekday.rawValue)
        return .normalized(.object(fields))
    }

    // MARK: - Reporting back

    /// The plan as it was written, so the caller sees what landed rather than
    /// what it sent.
    private static func reported(_ document: PlanDocument) -> JSONValue {
        [
            "id": .string(document.id.uuidString),
            "version": .integer(document.version),
            "catalogVersion": .integer(document.catalogVersion),
            "generatedAt": .date(document.generatedAt),
            "title": .string(document.title),
            "goal": .string(document.goal),
            "weekCount": .integer(document.weekCount),
            "durationMinutes": .integer(document.durationMinutes),
            "notes": .string(document.notes),
            "days": .array(
                document.days.map { day in
                    [
                        "weekday": .string(day.weekday.fullName),
                        "focus": .string(day.focus),
                        "durationMinutes": .integer(day.durationMinutes),
                        "exercises": .array(
                            day.exercises.map {
                                [
                                    "exerciseID": .string($0.exerciseID.rawValue),
                                    "displayName": .string($0.displayName),
                                    "sets": .integer($0.sets),
                                    "repRange": .string($0.repRange),
                                    "restSeconds": .integer($0.restSeconds),
                                    "suggestedLoad": .mass($0.suggestedLoad),
                                    "tempo": .string($0.tempo),
                                    "notes": .string($0.notes),
                                ]
                            }),
                    ]
                }),
        ]
    }

    /// A decoding failure said in terms of the argument that caused it.
    ///
    /// `DecodingError`'s own description names coding paths and Swift types,
    /// which is not something a caller can act on.
    private static func describe(decodingFailure error: any Error) -> String {
        let detail: String
        switch error as? DecodingError {
        case .keyNotFound(let key, let context):
            detail = "'\(key.stringValue)' is missing\(Self.location(context))."
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            detail = "a value has the wrong type\(Self.location(context))."
        case .dataCorrupted(let context):
            detail = "a value could not be read\(Self.location(context))."
        default:
            detail = "\(error)"
        }
        return "That plan could not be read, so nothing was written: \(detail) Every exercise "
            + "needs 'exerciseID', 'displayName' and 'sets'; every day needs 'weekday'."
    }

    private static func location(_ context: DecodingError.Context) -> String {
        let path = context.codingPath.map(\.stringValue).filter { !$0.isEmpty }
        return path.isEmpty ? "" : " at \(path.joined(separator: " → "))"
    }
}

/// What reading a day's `weekday` produced: a day whose weekday is now the
/// number the document decodes, or a sentence saying why it could not be.
///
/// A local result type rather than `Result`, because the failure here is a
/// message for Claude rather than an `Error` anything catches.
private enum WeekdayNormalization {
    case normalized(JSONValue)
    case refused(String)
}

extension Weekday {

    /// The weekday a name refers to, full or abbreviated, in any casing.
    ///
    /// Lives here rather than on `Weekday` in `LiftingKit` because it exists
    /// for one reason — accepting a day written in prose at the MCP boundary —
    /// and the shared type should keep exactly one way to decode.
    static func named(_ name: String) -> Weekday? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allCases.first { $0.fullName.lowercased() == needle }
            ?? allCases.first { $0.shortName.lowercased() == needle }
    }
}
