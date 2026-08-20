import Foundation
import LiftingKit

extension ToolRunner {

    /// Writes `profile-update.json` into the shared folder, recording what has
    /// been learned about the lifter, and returns exactly what was written.
    ///
    /// **This is the only way a fact about the lifter is recorded.** The app
    /// asks him nothing — there is no setup screen and no settings form for a
    /// training question — so what he says in conversation is written here or
    /// it is not written at all.
    ///
    /// **The update merges.** A field left out is left exactly as it is on the
    /// phone, which is what makes it safe to record one thing at a time
    /// ("actually I have a rack now") without restating, and possibly
    /// clobbering, everything else. A field set to `null` returns that fact to
    /// not-known, which is how something recorded in error is taken back rather
    /// than replaced with a second guess. A list — the equipment he owns,
    /// avoided patterns, avoided exercises, preferred days — replaces the stored
    /// list wholesale rather than adding to it, since a patch that could only
    /// add could never record a shoulder that healed.
    ///
    /// **Bodyweight and baselines are series, and behave differently on
    /// purpose.** Each record is filed under what it is about — a weigh-in under
    /// its day, a baseline under its lift — so sending one adds it where there
    /// was none and corrects it where there was one, and a trend is never
    /// destroyed by recording a single weigh-in.
    ///
    /// **His gym is what he owns, not a tier.** `equipment` takes the concrete
    /// types, so "barbell and bands but no rack" is sayable; the coarse tiers
    /// are accepted as shorthand and expand into the types they stand for. A
    /// type this build has never heard of is recorded rather than refused — it
    /// is a true fact about him, and it grants no catalog movement, which is
    /// honest.
    ///
    /// Three things are checked and nothing is changed: an avoided exercise and
    /// a baseline must each name a real catalog ID, and an avoided pattern must
    /// be one the catalog actually uses. The first two would key history on an
    /// identity nothing else will ever join; the third would be recorded as a
    /// filter that silently excludes nothing, which is worse than a refusal
    /// because it reads as having worked. Everything else is recorded verbatim.
    func updateProfile(_ arguments: JSONValue) -> ToolOutcome {
        let update: ProfileUpdate
        do {
            update = try makeUpdate(from: arguments)
        } catch let error as ProfileArgumentError {
            return .failure(error.message)
        } catch {
            return .failure("That profile update could not be read: \(error)")
        }

        guard !update.statesNothing else {
            return .failure(
                "\(ToolCatalog.updateProfile) was called without naming a single fact, so "
                    + "nothing was written. Pass the fields you have learned — omit the ones you "
                    + "have not, and pass null for one you want to return to not-known.")
        }

        let written: ProfileUpdate
        do {
            written = try update.superseding(waitingUpdate())
        } catch let error as ProfileArgumentError {
            return .failure(error.message)
        } catch {
            return .failure("The waiting profile update could not be read: \(error)")
        }

        do {
            try documents.writeProfileUpdate(written)
        } catch {
            return .failure(
                "The profile update could not be written to \(documents.profileUpdateLocation): "
                    + "\(error.localizedDescription) Nothing was saved, so the lifter's phone "
                    + "still has the old facts and the next snapshot will still report them.")
        }

        return .report([
            "writtenTo": .string(documents.profileUpdateLocation),
            "updateID": .string(written.id.uuidString),
            // The same question the plan's note answers: a file written into a
            // folder nothing syncs is recorded here and nowhere else.
            "note": .string(
                Self.deliveryNote(delivery(documents.profileUpdateLocation))
                    .replacingOccurrences(of: "Written", with: "Recorded")
                    .replacingOccurrences(of: "plan.", with: "update.")
                    + " Fields you did not name are untouched."),
            "recorded": Self.reported(written),
        ])
    }

    // MARK: - Not losing an update the phone has not seen

    /// The update already in the folder that the phone has not taken in yet, or
    /// `nil` when there is none to fold into this one.
    ///
    /// The folder holds one update at a time. Two calls in one conversation are
    /// the ordinary case — the lifter is at the desk, his phone is in his
    /// pocket — so overwriting would silently drop everything the first call
    /// recorded while reporting that it had been written.
    ///
    /// An update the snapshot says has already been applied is *not* folded in:
    /// re-stating facts the phone already has would re-impose them over
    /// anything changed since. A snapshot that cannot be read leaves that
    /// unknowable, and folding is then the safe answer — it can only repeat a
    /// fact, where overwriting would lose one.
    private func waitingUpdate() throws -> ProfileUpdate {
        guard let waiting = try readWaitingUpdate() else { return Self.nothingWaiting }
        guard waiting.id != lastAppliedUpdateID() else { return Self.nothingWaiting }
        return waiting
    }

    /// An update that states nothing, so folding onto it is a no-op.
    private static let nothingWaiting = ProfileUpdate(
        id: UUID(), generatedAt: Date(timeIntervalSince1970: 0))

    private func readWaitingUpdate() throws -> ProfileUpdate? {
        do {
            return try documents.readProfileUpdate()
        } catch {
            throw ProfileArgumentError(
                "There is already a profile update at \(documents.profileUpdateLocation) and it "
                    + "cannot be read: \(error.localizedDescription) Nothing was written, because "
                    + "replacing it would discard whatever it recorded. If iCloud is mid-sync, "
                    + "try again in a moment.")
        }
    }

    /// The update the phone last applied, as of the last snapshot it wrote.
    ///
    /// A missing or unreadable snapshot answers `nil`, which means "cannot
    /// tell" and makes the caller fold conservatively. It is not a failure:
    /// recording a fact about the lifter does not depend on his training log,
    /// and a lifter who has never opened the app still has things worth writing
    /// down about him.
    private func lastAppliedUpdateID() -> UUID? {
        do {
            return try documents.readSnapshot()?.profile?.appliedProfileUpdateID
        } catch {
            return nil
        }
    }

    // MARK: - Reporting back

    /// The update as it was written, said in the three states the app will read
    /// it in, so the caller sees what will actually happen on the phone rather
    /// than what it sent.
    private static func reported(_ update: ProfileUpdate) -> JSONValue {
        [
            "displayUnit": described(update.displayUnit) { .string($0.rawValue) },
            "experience": described(update.experience) { .string($0.rawValue) },
            "equipment": described(update.equipment) { .taxonomy($0) },
            "bodyweight": described(
                update.bodyweight.map { reading in
                    [
                        "date": .date(reading.resolvedDate(from: update.generatedAt)),
                        "mass": .mass(reading.mass),
                    ]
                }),
            "baselines": described(
                update.baselines.map { baseline in
                    [
                        "exerciseID": .string(baseline.exerciseID.rawValue),
                        "load": .mass(baseline.load),
                        "reps": .integer(baseline.reps),
                        "recordedAt": .date(baseline.resolvedDate(from: update.generatedAt)),
                    ]
                }),
            "goal": described(update.goal) { .string($0) },
            "constraints": described(update.constraints) { .string($0) },
            "avoidedPatterns": described(update.avoidedPatterns) { .taxonomy($0) },
            "avoidedExercises": described(update.avoidedExercises) {
                .array($0.map { .string($0.rawValue) })
            },
            "preferredWeekdays": described(update.preferredWeekdays) {
                .array($0.map { .string($0.fullName) })
            },
            "preferredDurationMinutes": described(update.preferredDurationMinutes) {
                .integer($0)
            },
        ]
    }

    private static func described<Value>(
        _ field: StatedValue<Value>, _ render: (Value) -> JSONValue
    ) -> JSONValue {
        switch field {
        case .unchanged: ["state": "left as it was"]
        case .unstated: ["state": "returned to not known"]
        case .stated(let value): ["state": "recorded", "value": render(value)]
        }
    }

    /// A series, in the two states a series has. There is no third: a list of
    /// records adds to and corrects what is stored, and an update that carries
    /// none of them says nothing about it rather than taking the series back.
    /// Every record is shown with the date it will actually be filed under, so
    /// the caller sees what the phone will do rather than what it sent.
    private static func described(_ records: [JSONValue]) -> JSONValue {
        records.isEmpty
            ? ["state": "left as it was"]
            : ["state": "recorded", "value": .array(records)]
    }
}
