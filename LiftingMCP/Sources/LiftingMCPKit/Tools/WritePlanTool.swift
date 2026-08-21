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
    /// the user never sees the prescription, which is worse than a refusal
    /// that can be read and corrected.
    ///
    /// The catalog version and timestamp are supplied here rather than asked
    /// for: they are facts about the write, and this is the code that knows
    /// them. **`routineID` is the exception, and it is what makes a routine
    /// grow.** Send the id the context resource reports and the blocks land on
    /// the routine the user is already on; omit it and the id is fresh, which
    /// starts a new routine and closes the one before it. Writing next week's
    /// block is the first; changing programme is the second, and nothing has to
    /// guess which was meant.
    func writePlan(_ arguments: JSONValue) -> ToolOutcome {
        guard arguments["sessions"] != nil else {
            return .failure(
                "write_plan needs a 'sessions' array — one entry per workout, each stating "
                    + "which block it belongs to and where it sits in that block. A session "
                    + "with no entries is a rest day and is fine; leaving the training out "
                    + "entirely is not a plan, so nothing was written.")
        }

        var fields = arguments.objectValue ?? [:]
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

        if let refusal = Self.refusalForARewrittenSession(in: document, documents: documents) {
            return .failure(refusal)
        }

        do {
            try documents.writePlan(document)
        } catch {
            return .failure(
                "The plan could not be written to \(documents.planLocation): "
                    + "\(error.localizedDescription) Nothing was saved, so the user's phone "
                    + "will not see this plan.")
        }

        let sessions = document.sessions
        return .report([
            "writtenTo": .string(documents.planLocation),
            "blockCount": .integer(document.blockOrdinals.count),
            "sessionCount": .integer(sessions.count),
            "exerciseCount": .integer(sessions.reduce(0) { $0 + $1.exercises.count }),
            "note": .string(Self.deliveryNote(delivery(documents.planLocation))),
            "plan": Self.reported(document),
        ])
    }

    /// What to say about a plan that has been written, given what iCloud will
    /// do with it.
    ///
    /// **"Written" is not "arrived".** The file went into the folder; carrying
    /// it to the phone is iCloud's, and on a Mac that is not syncing the
    /// container — or an account with no room left — it never happens. Saying
    /// the app will import it in that state is the tool reporting a success
    /// nobody got.
    static func deliveryNote(_ prospect: ToolRunner.DeliveryProspect) -> String {
        switch prospect {
        case .onItsWay:
            "Written. The app imports it the next time it is opened or comes forward."
        case .notShared:
            "Written to a folder iCloud is not syncing, so the phone will not see this "
                + "plan. Point the server at the app's iCloud container."
        }
    }

    /// Why this plan will be turned away by the phone, if it will be.
    ///
    /// **The refusal belongs where the coach can see it.** The app refuses a
    /// plan that rewrites a block already trained, and it is right to: a set he
    /// ticked is the record of what happened. But that refusal reaches the
    /// user's screen, not this conversation — the tool would answer
    /// "Written." and the plan would land nowhere, which is the one failure
    /// this project refuses everywhere else. So the same question is asked here,
    /// against the record the snapshot carries, and answered in the same turn
    /// the plan was written in.
    ///
    /// **The phone stays the authority.** The snapshot can be older than the
    /// store — a block trained since it was written looks untrained here — so
    /// this catches earlier, never instead. Anything it misses the app still
    /// refuses.
    /// Why a plan may not be written, when it rewrites something he has trained.
    ///
    /// **The server refuses before the phone has to.** The app refuses this too
    /// — that is where the rule is enforced — but a coach who is told at write
    /// time can fix it in the same breath, and one who is told by a phone alert
    /// hours later cannot.
    ///
    /// It names the session rather than the block. A plan is a flat list of
    /// sessions now, so changing one does not put the rest of its block out of
    /// reach.
    static func refusalForARewrittenSession(
        in document: PlanDocument, documents: any TrainingDocuments
    ) -> String? {
        guard let snapshot = try? documents.readSnapshot() else { return nil }
        let trained = Set(
            TrainingLog.trained(in: snapshot).map {
                SessionCoordinates(block: $0.blockOrdinal, ordinal: $0.ordinal)
            })

        for arriving in document.sessions {
            let key = SessionCoordinates(
                block: arriving.blockOrdinal, ordinal: arriving.ordinal)
            guard trained.contains(key) else { continue }
            guard let stored = snapshot.sessions.first(where: {
                $0.blockOrdinal == arriving.blockOrdinal && $0.ordinal == arriving.ordinal
            }) else { continue }
            guard stored.prescription != arriving else { continue }
            return """
                This plan changes session \(arriving.ordinal) of block \
                \(arriving.blockOrdinal), which he has already trained. A set he ticked, or \
                a session he marked finished, is the record of what happened and cannot be \
                rewritten. Nothing was written. Send that session exactly as it stands, and \
                the change in one he has not reached.
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
        for day in document.sessions {
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
        for day in document.sessions {
            for exercise in day.exercises where catalog.exercise(id: exercise.exerciseID) == nil {
                return exercise.exerciseID
            }
        }
        return nil
    }


}
