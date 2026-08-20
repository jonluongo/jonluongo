import Foundation
import Testing
import LiftingKit
@testable import LiftingMCPKit

/// Claude does not know what he has not been told, and nothing in a report says
/// "this field is empty" — a null looks the same whether nobody asked or the
/// answer was nothing. This is the tool that says which is which, and the whole
/// of what it may say: which fields the record has, and which are empty.
@Suite("Unstated facts")
struct UnstatedFactsTests {

    /// A lifter about whom literally nothing has been recorded: no profile, no
    /// weigh-in, no baseline, no block. The ordinary state of the very first
    /// conversation, since the app asks him nothing.
    private static let nothingKnown = TrainingSnapshot(
        catalogVersion: 5, generatedAt: daysAgo(1))

    private func facts(in snapshot: TrainingSnapshot) throws -> JSONValue {
        try #require(
            try makeRunner(documents: InMemoryDocuments(snapshot: snapshot))
                .call(ToolCatalog.unstatedFacts, arguments: [:]).report)
    }

    private func names(_ report: JSONValue) throws -> [String] {
        try #require(report["unstated"]?.arrayValue).compactMap { $0["fact"]?.stringValue }
    }

    // MARK: - The two ends of the range

    @Test("A lifter nobody has said anything about has every fact reported as unstated")
    func nothingStatedNamesEverything() throws {
        let report = try facts(in: Self.nothingKnown)

        #expect(try names(report) == LifterFacts.known.map(\.name))
        #expect(report["stated"] == .array([]))
    }

    @Test("A lifter who has stated everything is reported as having no gaps")
    func everythingStatedNamesNothing() throws {
        let report = try facts(in: fixtureSnapshot())

        #expect(try names(report).isEmpty)
        #expect(try #require(report["stated"]?.arrayValue).count == LifterFacts.known.count)
    }

    @Test("The two lists together are every fact the record can hold, always")
    func bothListsAccountForEveryFact() throws {
        let report = try facts(
            in: fixtureSnapshot(
                profile: fixtureProfile(experience: nil, availableEquipment: nil)))
        let stated = try #require(report["stated"]?.arrayValue)
            .compactMap { $0["fact"]?.stringValue }

        #expect(try names(report) == ["equipment", "experience"])
        #expect((try names(report) + stated).sorted() == LifterFacts.known.map(\.name).sorted())
    }

    @Test("A stated fact carries the date he last said it")
    func aStatedFactCarriesItsDate() throws {
        // The date is the thing that could not be read anywhere before. A
        // constraint stated eighteen months ago and one stated on Tuesday were
        // the same word in this list.
        let report = try facts(in: fixtureSnapshot())
        let stated = try #require(report["stated"]?.arrayValue)
        // Read through `objectValue`: the subscript answers `nil` for an
        // explicit null as readily as for an absent key, so `!= .null` on it is
        // an assertion that passes whatever the report says.
        let constraints = try #require(stated.first { $0["fact"] == "constraints" }?.objectValue)
        let goal = try #require(stated.first { $0["fact"] == "goal" }?.objectValue)

        #expect(constraints["statedAt"] != .null)
        #expect(goal["statedAt"] != .null)
        #expect(constraints["statedAt"] != goal["statedAt"], "said on different days")
    }

    @Test("A fact whose date is not on record says so, rather than reading as today")
    func anUndatedStatedFactIsNull() throws {
        // Every record predating the phone keeping dates is this. Filling one
        // in would claim he restated everything the day he updated the app.
        let report = try facts(
            in: fixtureSnapshot(profile: fixtureProfile(statedAt: [:])))
        let stated = try #require(report["stated"]?.arrayValue)

        #expect(stated.allSatisfy { $0.objectValue?["statedAt"] == .null })
        #expect(!stated.isEmpty, "and they are still stated facts")
    }

    @Test("What the tool advertises matches what it returns")
    func theDescriptionNamesTheDates() throws {
        // The description said it reports "empty fields and nothing more" for
        // as long as that was true, and a description that understates a tool
        // is a field the reader never looks at. It is the only text the coach
        // sees before deciding whether to call.
        let described = ToolCatalog.unstatedFactsDefinition.description.lowercased()
        let report = try facts(in: fixtureSnapshot())
        let carriesDates = try #require(report["stated"]?.arrayValue)
            .contains { $0.objectValue?["statedAt"] != .null }

        #expect(carriesDates, "the report carries dates")
        #expect(described.contains("date"), "and the description says so")
        // The specific claim that stopped being true, named rather than left to
        // a word count: "empty fields and nothing more" was accurate until the
        // dates arrived, and checking only that *some* sentence says "date"
        // does not catch a description that promises less than it returns.
        #expect(!described.contains("nothing more"))
    }

    @Test("Nothing in the report calls a date old")
    func theServerPassesNoJudgementOnADate() throws {
        // Whether eighteen months is stale is a training judgement, and the one
        // thing this server does not do is make those.
        let report = try facts(in: fixtureSnapshot())
        let note = try #require(report["note"]?.stringValue).lowercased()

        for verdict in ["stale", "out of date", "outdated", "too old", "should ask"] {
            #expect(!note.contains(verdict), "the note passes a verdict: \(verdict)")
        }
    }

    // MARK: - What it says about a gap

    @Test("An unstated fact says what the record holds there, not just its name")
    func aGapSaysWhatWouldGoInIt() throws {
        let unstated = try #require(try facts(in: Self.nothingKnown)["unstated"]?.arrayValue)
        let equipment = try #require(unstated.first { $0["fact"] == "equipment" })

        #expect(try #require(equipment["holds"]?.stringValue).contains("owns"))
        #expect(unstated.allSatisfy { $0["holds"]?.stringValue?.isEmpty == false })
    }

    @Test("It names the tool that closes a gap, since naming one with no way through is no use")
    func itNamesWhatClosesAGap() throws {
        let report = try facts(in: Self.nothingKnown)

        #expect(report["statedWith"]?.stringValue == ToolCatalog.updateProfile)
        #expect(try #require(report["note"]?.stringValue).contains(ToolCatalog.updateProfile))
    }

    @Test("It reports empty fields and leaves every judgement about them to the reader")
    func itDecidesNothing() throws {
        let note = try #require(try facts(in: Self.nothingKnown)["note"]?.stringValue)
        let description = ToolCatalog.unstatedFactsDefinition.description

        // The line this tool has to hold: "equipment is unstated" is a fact
        // about the record; "ask about equipment before writing a split" is a
        // training opinion, and it is not this server's to hold.
        #expect(note.contains("yours to judge"))
        #expect(description.contains("yours to judge"))
    }

    // MARK: - Where a fact can be stated from

    @Test("A weigh-in in the series counts as stated even with none on the profile")
    func bodyweightCanComeFromTheSeries() throws {
        let snapshot = TrainingSnapshot(
            catalogVersion: 5, generatedAt: daysAgo(1),
            bodyMetrics: [
                SnapshotBodyMetric(date: daysAgo(2), bodyweight: Mass(value: 182, unit: .pounds))
            ])

        #expect(!(try names(facts(in: snapshot)).contains("bodyweight")))
    }

    @Test("A lifter with no stated starting strength is told so — a first block has no anchor")
    func baselinesAreSurveyed() throws {
        let snapshot = TrainingSnapshot(
            catalogVersion: 5, generatedAt: daysAgo(1), profile: fixtureProfile())

        #expect(try names(facts(in: snapshot)).contains("baselines"))
        #expect(!(try names(facts(in: fixtureSnapshot())).contains("baselines")))
    }

    // MARK: - The guard on drift

    @Test("Every fact it names is one update_profile can actually close")
    func everyFactIsWritable() {
        for fact in LifterFacts.known {
            #expect(
                ProfileUpdate.statedKeys.contains(fact.name),
                "'\(fact.name)' is reported as missing with no way to state it")
        }
    }

    @Test("Every fact the document can hold is surveyed, or deliberately left out by name")
    func noFactGoesUnreported() {
        let surveyed = Set(LifterFacts.known.map(\.name))

        // A key added to `ProfileUpdate` and to neither list fails here rather
        // than becoming a fact the record can hold and no report ever mentions.
        #expect(surveyed.union(LifterFacts.unsurveyedKeys) == ProfileUpdate.statedKeys)
        #expect(surveyed.isDisjoint(with: LifterFacts.unsurveyedKeys))
    }

    // MARK: - Not a substitute for a snapshot

    @Test("With no snapshot it fails rather than reporting a lifter nobody has asked")
    func aMissingSnapshotIsNotAnEmptyLifter() throws {
        let outcome = try makeRunner(documents: InMemoryDocuments())
            .call(ToolCatalog.unstatedFacts, arguments: [:])

        // "Nothing is stated about him" and "the file was never written" read
        // identically in this report and are not the same thing.
        #expect(outcome.report == nil)
        #expect(try #require(outcome.failureMessage).contains("snapshot.json"))
    }

    // MARK: - The same answer everywhere

    @Test("The context resource and the tool report the same gaps")
    func theResourceAndTheToolAgree() throws {
        let snapshot = fixtureSnapshot(
            profile: fixtureProfile(experience: nil, availableEquipment: nil))
        let documents = InMemoryDocuments(snapshot: snapshot)
        let runner = try makeRunner(documents: documents)

        let carried = try #require(runner.contextResource().report?["lifter"]?["unstated"])

        #expect(carried == .array(try names(facts(in: snapshot)).map { .string($0) }))
    }

    @Test("The server tells Claude at the handshake that the record has gaps and where to look")
    func theHandshakeSaysTheRecordHasGaps() {
        #expect(MCPServer.instructions.contains(ToolCatalog.unstatedFacts))
    }
}

/// `write_plan` succeeds for a lifter nothing is known about — it must, or a
/// first block would be impossible. What it can do is say what was still empty
/// when the plan landed, which is the moment that fact is worth the most.
@Suite("What was unstated when a plan was written")
struct UnstatedAtWriteTests {

    private static let plan: JSONValue = [
        "title": "First block",
        "days": [[
            "weekday": "monday",
            "exercises": [[
                "exerciseID": "barbell-squat", "displayName": "Barbell Squat", "sets": 3,
            ]],
        ]],
    ]

    private func written(with documents: InMemoryDocuments) throws -> JSONValue {
        try #require(
            try makeRunner(documents: documents)
                .call(ToolCatalog.writePlan, arguments: Self.plan).report)
    }

    @Test("A plan for a lifter nobody has asked is written, and says what was unstated")
    func itReportsTheGapsWithoutWithholdingThePlan() throws {
        let documents = InMemoryDocuments(
            snapshot: TrainingSnapshot(catalogVersion: 5, generatedAt: daysAgo(1)))

        let report = try written(with: documents)
        let facts = try #require(report["unstatedWhenWritten"]?["facts"]?.arrayValue)

        #expect(documents.lastWrittenPlan?.title == "First block")
        #expect(facts.compactMap(\.stringValue) == LifterFacts.known.map(\.name))
    }

    @Test("A plan for a lifter who has stated everything reports nothing unstated")
    func itSaysSoWhenThereIsNothingMissing() throws {
        let report = try written(with: InMemoryDocuments(snapshot: fixtureSnapshot()))

        #expect(report["unstatedWhenWritten"]?["facts"] == .array([]))
    }

    @Test("With no snapshot to read, what was unstated is null rather than nothing")
    func anUnreadableRecordIsUnknownNotEmpty() throws {
        let documents = InMemoryDocuments()

        let report = try written(with: documents)

        // An empty list here would say every fact was stated, which is the one
        // answer that is certainly wrong.
        #expect(report.objectValue?["unstatedWhenWritten"]?.objectValue?["facts"] == .null)
        #expect(documents.lastWrittenPlan != nil, "the plan is written either way")
        #expect(try #require(report["unstatedWhenWritten"]?["note"]?.stringValue)
            .contains("unknown rather than none"))
    }
}
