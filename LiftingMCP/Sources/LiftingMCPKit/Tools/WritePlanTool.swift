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
    /// **A routine is a list of blocks and they may differ.** Block 3 can prescribe
    /// heavier work than week 1 and week 4 can be a deload; each week states its
    /// own days. A single-week block states one week. Nothing here repeats a
    /// week or fills one in — an unstated week is a week that was not written.
    ///
    /// **A key this format does not have fails the call with the key named**,
    /// rather than being dropped. A dropped key is reported as "Written" while
    /// the lifter never sees the prescription, which is worse than a refusal
    /// that can be read and corrected.
    ///
    /// The catalog version and timestamp are supplied here rather than asked
    /// for: they are facts about the write, and this is the code that knows
    /// them. **`routineID` is the exception, and it is what makes a routine
    /// grow.** Send the id the context resource reports and the blocks land on
    /// the routine the lifter is already on; omit it and the id is fresh, which
    /// starts a new routine and closes the one before it. Writing next week's
    /// block is the first; changing programme is the second, and nothing has to
    /// guess which was meant.
    func writePlan(_ arguments: JSONValue) -> ToolOutcome {
        guard arguments["blocks"] != nil || arguments["weeks"] != nil
            || arguments["days"] != nil
        else {
            return .failure(
                "write_plan needs a 'blocks' array — one entry per block of the routine, each "
                    + "with its own 'days'. A routine of a single block is one entry. A day with "
                    + "no exercises is a rest day and is fine; leaving the routine's training out "
                    + "entirely is not a plan, so nothing was written.")
        }

        var fields = arguments.objectValue ?? [:]
        switch Self.normalizedTraining(in: fields) {
        case .normalized(let normalized): fields = normalized
        case .refused(let message): return .failure(message)
        }
        fields["version"] = .integer(PlanDocument.currentVersion)
        // A stated routine has to be a routine: a malformed id silently
        // becoming a fresh one would start a new routine and supersede the one
        // he is training, which is the opposite of what was asked for.
        let stated = fields.removeValue(forKey: "routineID")?.stringValue
        if let stated, UUID(uuidString: stated) == nil {
            return .failure(
                "'routineID' must be the routine's id exactly as the context resource reports "
                    + "it. '\(stated)' is not one, and nothing was written. Leave it out "
                    + "entirely to start a new routine.")
        }
        fields["id"] = .string(stated ?? UUID().uuidString)
        fields["catalogVersion"] = .integer(catalog.version)
        fields["generatedAt"] = .date(now())

        let decoded: PlanDocument
        do {
            decoded = try JSONValue.object(fields)
                .decoded(as: PlanDocument.self, using: PlanDocument.makeDecoder())
        } catch let refusal as DocumentRefusal {
            return .failure(refusal.errorDescription ?? "\(refusal)")
        } catch {
            return .failure(Self.describe(decodingFailure: error))
        }

        if let unknown = Self.firstUnknownExercise(in: decoded, using: catalog) {
            return .failure(
                "This plan prescribes '\(unknown.rawValue)', which is not in the exercise "
                    + "catalog (version \(catalog.version)). Nothing was written. Find the real "
                    + "ID with \(ToolCatalog.listExercises) and call write_plan again — history "
                    + "is keyed on exercise identity, so an invented ID would fragment a lift's "
                    + "history irreparably.")
        }

        // Named after the IDs are checked, so a movement whose ID is wrong is
        // reported as a wrong ID rather than quietly acquiring a name.
        let document = decoded.named(using: catalog)

        if let unknown = Self.firstUnknownIcon(in: document) {
            return .failure(
                "This plan marks a session '\(unknown.rawValue)', which is not one of the "
                    + "marks the app can draw. Nothing was written. Choose one of: "
                    + SessionIcon.all.map(\.rawValue).joined(separator: ", ")
                    + " — or omit `icon`, which leaves the session unmarked.")
        }

        if let refusal = Self.refusalForARewrittenBlock(in: document, documents: documents) {
            return .failure(refusal)
        }

        do {
            try documents.writePlan(document)
        } catch {
            return .failure(
                "The plan could not be written to \(documents.planLocation): "
                    + "\(error.localizedDescription) Nothing was saved, so the lifter's phone "
                    + "will not see this plan.")
        }

        let days = document.blocks.flatMap(\.days)
        return .report([
            "writtenTo": .string(documents.planLocation),
            "weekCount": .integer(document.blockCount),
            "dayCount": .integer(days.count),
            "exerciseCount": .integer(days.reduce(0) { $0 + $1.exercises.count }),
            "note": "Written. The app imports it the next time it is opened or comes forward.",
            "plan": Self.reported(document),
            "unstatedWhenWritten": unstatedWhenWritten(),
        ])
    }

    /// Why this plan will be turned away by the phone, if it will be.
    ///
    /// **The refusal belongs where the coach can see it.** The app refuses a
    /// plan that rewrites a block already trained, and it is right to: a set he
    /// ticked is the record of what happened. But that refusal reaches the
    /// lifter's screen, not this conversation — the tool would answer
    /// "Written." and the plan would land nowhere, which is the one failure
    /// this project refuses everywhere else. So the same question is asked here,
    /// against the record the snapshot carries, and answered in the same turn
    /// the plan was written in.
    ///
    /// **The phone stays the authority.** The snapshot can be older than the
    /// store — a block trained since it was written looks untrained here — so
    /// this catches earlier, never instead. Anything it misses the app still
    /// refuses.
    static func refusalForARewrittenBlock(
        in document: PlanDocument, documents: any TrainingDocuments
    ) -> String? {
        guard let snapshot = try? documents.readSnapshot(),
            let stored = snapshot.routines.first(where: { $0.document.id == document.id })
        else { return nil }

        let trainedOrdinals = Set(
            stored.sessions.filter { $0.completedAt != nil }.map(\.blockOrdinal)
        ).union(snapshot.log.filter { $0.routineID == document.id && $0.isCompleted }
            .map(\.blockOrdinal))

        for ordinal in trainedOrdinals.sorted() {
            let index = ordinal - 1
            let asStored = stored.document.blocks.indices.contains(index)
                ? stored.document.blocks[index] : nil
            let arriving = document.blocks.indices.contains(index)
                ? document.blocks[index] : nil
            guard arriving != asStored else { continue }
            return """
                This plan changes block \(ordinal), which he has already trained. A set he \
                ticked, or a session he marked finished, is the record of what happened and a \
                plan may not rewrite it — the app would refuse this one on arrival, so nothing \
                was written here either. Send block \(ordinal) exactly as it stands and put the \
                change in a later block.
                """
        }
        return nil
    }

    /// The first mark this build cannot draw, in document order.
    ///
    /// Refused here rather than left to the phone for the same reason an unknown
    /// exercise is: the writer is told now, while he is still writing, instead of
    /// having a whole plan refused at import for a value he could have corrected
    /// in the call. The set is `SessionIcon.all`, which is also what the schema
    /// offers, so the two cannot disagree about what is allowed.
    private static func firstUnknownIcon(in document: PlanDocument) -> SessionIcon? {
        for day in document.blocks.flatMap(\.days) {
            guard let icon = day.icon, !icon.isKnown else { continue }
            return icon
        }
        return nil
    }

    /// The first ID the catalog does not have, in document order, so the error
    /// names the one to fix rather than an arbitrary one.
    private static func firstUnknownExercise(
        in document: PlanDocument, using catalog: any ExerciseCatalogProviding
    ) -> ExerciseID? {
        for day in document.blocks.flatMap(\.days) {
            for exercise in day.exercises where catalog.exercise(id: exercise.exerciseID) == nil {
                return exercise.exerciseID
            }
        }
        return nil
    }

    // MARK: - Weekdays, however they were written

    /// The call's fields with every weekday written as the number `Weekday`
    /// decodes from, wherever the block stated its training.
    ///
    /// A routine may state `blocks`, each with its own days, or bare `days` for
    /// a routine of one. Both are normalized here so the document decoder sees
    /// one shape; stating more than one is left to the decoder, which refuses
    /// it. `weeks` is the same list under the name the format used before
    /// version 5 — accepted and carried through unchanged, so a coach who
    /// learned the old word mid-conversation is not refused for it.
    private static func normalizedTraining(
        in fields: [String: JSONValue]
    ) -> FieldNormalization {
        var fields = fields
        for key in ["blocks", "weeks"] {
            guard let blocks = fields[key]?.arrayValue else { continue }
            var normalized: [JSONValue] = []
            for block in blocks {
                guard var members = block.objectValue else {
                    // Not an object at all: leave it for the decoder, whose
                    // complaint about the shape is the accurate one.
                    normalized.append(block)
                    continue
                }
                if let days = members["days"]?.arrayValue {
                    switch normalizedDays(days) {
                    case .normalized(let days): members["days"] = days
                    case .refused(let message): return .refused(message)
                    }
                }
                normalized.append(.object(members))
            }
            fields[key] = .array(normalized)
        }
        if let days = fields["days"]?.arrayValue {
            switch normalizedDays(days) {
            case .normalized(let days): fields["days"] = days
            case .refused(let message): return .refused(message)
            }
        }
        return .normalized(fields)
    }

    private static func normalizedDays(_ days: [JSONValue]) -> DayNormalization {
        var normalized: [JSONValue] = []
        for day in days {
            switch normalizeWeekday(in: day) {
            case .normalized(let day): normalized.append(day)
            case .refused(let message): return .refused(message)
            }
        }
        return .normalized(.array(normalized))
    }

    /// Turns a day's `weekday` into the number `Weekday` decodes from.
    ///
    /// `Weekday` is stored as `Calendar`'s 1-based numbering, which is exact
    /// and easy to get wrong from memory, so a name is accepted too. This
    /// translates at the edge rather than loosening the shared type — the phone
    /// and the server must keep decoding the document identically.
    private static func normalizeWeekday(in day: JSONValue) -> DayNormalization {
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
}

/// What rewriting part of a call produced: the part with every weekday now the
/// number the document decodes, or a sentence saying why it could not be.
///
/// A local result type rather than `Result`, because the failure here is a
/// message for Claude rather than an `Error` anything catches.
private enum Normalization<Value> {
    case normalized(Value)
    case refused(String)
}

private typealias FieldNormalization = Normalization<[String: JSONValue]>
private typealias DayNormalization = Normalization<JSONValue>

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
