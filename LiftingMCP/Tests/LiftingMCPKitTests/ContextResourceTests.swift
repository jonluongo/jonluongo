import Foundation
import Testing
import LiftingKit
@testable import LiftingMCPKit

/// The resource that rides along on every turn. It has to be small enough to
/// carry constantly and complete enough that the drill-down tools are only
/// needed when depth is actually wanted.
@Suite("Context resource")
struct ContextResourceTests {

    private func context(profile: SnapshotProfile? = fixtureProfile()) throws -> JSONValue {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot(profile: profile))
        return try #require(try makeRunner(documents: documents).contextResource().report)
    }

    @Test("It says who the lifter is and what he asked for")
    func identity() throws {
        let lifter = try #require(try context()["lifter"])

        #expect(lifter["experience"]?.stringValue == "intermediate")
        #expect(lifter["goal"]?.stringValue == "Add 20 lb to the bench")
        #expect(lifter["constraints"]?.stringValue == "Left shoulder is touchy overhead")
        #expect(lifter["bodyweight"] == ["value": 182.0, "unit": "lb"])
        #expect(lifter["displayUnit"]?.stringValue == "lb")
        #expect(lifter["preferredDurationMinutes"] == 60)
    }

    @Test("Each fact carries the date it was stated, not one date for all of them")
    func factsCarryTheirOwnDates() throws {
        // The whole reason `statedAt` replaced a single `updatedAt`: a goal
        // stated two months ago and a constraint stated over a year ago read
        // identically without it, and they are not the same instruction.
        let stated = try #require(try context()["lifter"]?["statedAt"]?.objectValue)

        #expect(stated["goal"] != nil)
        #expect(stated["constraints"] != nil)
        #expect(stated["goal"] != stated["constraints"], "different days, different dates")
    }

    @Test("A fact with no date on record is absent rather than dated today")
    func anUndatedFactIsAbsent() throws {
        // Absent means the date is not on record — stated before the phone kept
        // them, or never stated. Filling it in with today would say he
        // mentioned his equipment this morning.
        let stated = try #require(try context()["lifter"]?["statedAt"]?.objectValue)

        #expect(stated["equipment"] == nil)
    }

    @Test("Free text nobody has given is null, like every other fact he has not stated")
    func unstatedFreeTextIsNull() throws {
        // The store spells absent free text as an empty string. Carrying that
        // spelling onto the wire made `goal` say "" while `experience` said
        // null — two ways of saying "he has not said" in one object, with
        // unstated_facts listing the goal it appeared to have.
        let lifter = try #require(
            try context(profile: fixtureProfile(experience: nil, goal: "", constraints: ""))
                .objectValue?["lifter"])

        #expect(lifter.objectValue?["goal"] == .null)
        #expect(lifter.objectValue?["constraints"] == .null)
        #expect(lifter.objectValue?["experience"] == .null, "the one that was always right")
    }

    @Test("Free text he has given is reported as he gave it")
    func statedFreeTextSurvives() throws {
        let lifter = try #require(try context()["lifter"])

        #expect(lifter["goal"]?.stringValue == "Add 20 lb to the bench")
        #expect(lifter["constraints"]?.stringValue == "Left shoulder is touchy overhead")
    }

    @Test("It says what he has to train with and what he will not train")
    func equipmentAndConstraints() throws {
        let lifter = try #require(try context(
            profile: fixtureProfile(
                availableEquipment: [.bodyweight, .dumbbell, .plate],
                avoidedPatterns: [.hinge],
                avoidedExercises: [ExerciseID(rawValue: "barbell-deadlift")]))["lifter"])

        #expect(lifter["availableEquipment"] == ["bodyweight", "dumbbell", "plate"])
        #expect(lifter["avoidedPatterns"] == ["hinge"])
        #expect(lifter["avoidedExercises"] == ["barbell-deadlift"])
    }

    @Test("It says which block he is on, and not the ones he has finished")
    func currentBlock() throws {
        let block = try #require(try context()["currentBlock"])

        #expect(block["title"]?.stringValue == "Autumn strength")
        // The count of weeks the plan states, rather than a separately stored
        // number that could disagree with it.
        #expect(block["blocksPrescribed"] == 2)
        #expect(block["weekdays"] == ["Monday", "Thursday"])
        #expect(block["durationMinutes"] == 60)
        #expect(block["blocksLogged"] == 1)
    }

    @Test("The days it lists are the current block's, not every block's at once")
    func daysAreOneBlocksOwn() throws {
        let block = try #require(try context()["currentBlock"])
        let days = try #require(block["days"]?.arrayValue)

        // The fixture is two blocks: the first trained through, the second
        // holding one unfinished Push day. Flattened, this reported three days
        // under a key that names one block, with nothing saying where the
        // boundary was.
        #expect(block["currentBlockOrdinal"] == 2)
        #expect(block["currentBlockLabel"]?.stringValue == "Accumulation")
        #expect(block["currentBlockIsDeload"] == false)
        #expect(days.count == 1)
        #expect(days.first?["focus"]?.stringValue == "Push")
        #expect(days.first?["weekday"]?.stringValue == "Monday")
    }

    @Test("It says plainly when nothing is prescribed past the block he is on")
    func nothingPrescribedBeyond() throws {
        // Every session of every block finished, and the last block is the one
        // he is on: there is nothing left to train until a plan arrives.
        let spent = fixtureRoutine(
            title: "Autumn strength", startDate: daysAgo(14),
            blocks: [
                (label: "Accumulation", isDeload: false, days: [
                    fixtureDay(weekday: .monday, focus: "Push", completedAt: daysAgo(2),
                               exercises: [])
                ])
            ])
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot(blocks: [spent]))
        let report = try #require(try makeRunner(documents: documents).contextResource().report)
        let block = try #require(report["currentBlock"])

        #expect(block["nothingPrescribedBeyond"] == true)
        #expect(try context()["currentBlock"]?["nothingPrescribedBeyond"] == false)
    }

    @Test("It says how many sessions the record holds, not just the ones it carries")
    func theCarriedSessionsAreCountedAgainstTheWhole() throws {
        let report = try #require(try context())

        // The fixture holds three: two in the block he is on and one in the
        // block before it. Five entries and no total would read as the record
        // itself rather than as the end of it.
        #expect(report["sessionsLogged"] == 3)
        #expect(try #require(report["recentSessions"]?.arrayValue).count == 3)
    }

    @Test("A record longer than the summary says so rather than ending quietly")
    func aTruncatedSummaryStatesTheWhole() throws {
        // Eight sessions, five carried. Without the total this reads as a
        // lifter who has trained five times — the summary mistaken for the
        // record, which is the failure the cap creates and the count closes.
        let days = (0..<8).map { index in
            fixtureDay(
                weekday: Weekday.displayOrder[index % Weekday.displayOrder.count],
                focus: "Push", completedAt: daysAgo(index + 1),
                exercises: [
                    prescribed(
                        "barbell-bench-press", "Barbell Bench Press",
                        sets: 1, reps: "5", load: 185, rest: 120,
                        logged: [set(0, 185, 5, at: daysAgo(index + 1))])
                ])
        }
        let long = fixtureRoutine(
            title: "Long block", startDate: daysAgo(60),
            blocks: [(label: "Accumulation", isDeload: false, days: days)])
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot(blocks: [long]))
        let report = try #require(try makeRunner(documents: documents).contextResource().report)

        #expect(report["sessionsLogged"] == 8)
        #expect(try #require(report["recentSessions"]?.arrayValue).count
            == ContextReport.carriedSessions)
    }

    @Test("A session nobody named, in a block nobody labelled, says so with null")
    func unnamedTrainingIsNull() throws {
        // Same rule as the lifter's goal, one object over: the document format
        // writes an unnamed focus as an empty string because it has nowhere to
        // put an absent one, and `""` beside `null` for the same fact leaves a
        // reader guessing whether it was left blank or made empty on purpose.
        let bare = fixtureRoutine(
            title: "", startDate: daysAgo(7),
            blocks: [(label: nil, isDeload: false, days: [
                fixtureDay(
                    weekday: .monday, completedAt: daysAgo(1),
                    exercises: [
                        prescribed(
                            "barbell-bench-press", "Barbell Bench Press", sets: 1, reps: "5",
                            load: 185, rest: 120,
                            logged: [set(0, 185, 5, at: daysAgo(1))])
                    ])
            ])])
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot(blocks: [bare]))
        let report = try #require(try makeRunner(documents: documents).contextResource().report)
        let block = try #require(report.objectValue?["currentBlock"])
        let session = try #require(report["recentSessions"]?[0])

        #expect(block.objectValue?["title"] == .null)
        #expect(block.objectValue?["goal"] == .null)
        #expect(block.objectValue?["currentBlockLabel"] == .null)
        #expect(session.objectValue?["focus"] == .null)
        #expect(session.objectValue?["plan"] == .null)
    }

    @Test("It says what he did lately, compactly")
    func recentSessions() throws {
        let sessions = try #require(try context()["recentSessions"]?.arrayValue)

        #expect(sessions.first?["focus"]?.stringValue == "Push")
        #expect(sessions.first?["date"] == JSONValue.date(daysAgo(2)))
        #expect(sessions.first?["exercises"] != nil)
    }

    @Test("It says what he is currently working with on each lift he has trained")
    func workingWeights() throws {
        let weights = try #require(try context()["workingWeights"]?.arrayValue)
        let bench = try #require(weights.first { $0["exerciseID"] == "barbell-bench-press" })

        #expect(bench["load"] == ["value": 225.0, "unit": "lb"])
        // The last working set he finished was the short one — four reps, not
        // the five he was prescribed. Reported as it happened.
        #expect(bench["reps"] == 4)
        #expect(bench["lastTrained"] == JSONValue.date(daysAgo(2)))
        #expect(bench["displayName"]?.stringValue == "Barbell Bench Press")
    }

    @Test("A working weight is the last completed working set, never a warmup")
    func warmupsAreNotWorkingWeights() throws {
        let weights = try #require(try context()["workingWeights"]?.arrayValue)
        let bench = try #require(weights.first { $0["exerciseID"] == "barbell-bench-press" })

        #expect(bench["load"] != ["value": 135.0, "unit": "lb"])
    }

    @Test("It says how old the snapshot is, so stale data cannot pass for current")
    func staleness() throws {
        let report = try context()

        #expect(report["snapshotGeneratedAt"] == JSONValue.date(daysAgo(1)))
        #expect(report["snapshotAgeDays"] == 1)
        #expect(report["catalogVersion"] == 5)
    }

    @Test("It points at the tools rather than trying to carry everything itself")
    func pointsAtTheTools() throws {
        #expect(try #require(try context()["note"]?.stringValue).contains(ToolCatalog.listExercises))
    }

    @Test("A lifter nothing is recorded about is described honestly, not invented")
    func noProfileIsHonest() throws {
        let report = try context(profile: nil)

        // Reported as JSON null rather than as an invented profile.
        #expect(report.objectValue?["lifter"] == .null)
        let note = try #require(report["note"]?.stringValue)
        #expect(note.contains("Nothing has been recorded"))
        #expect(note.contains(ToolCatalog.updateProfile))
    }

    @Test("A fact nobody has stated reads as null, never as a plausible default")
    func unstatedFactsAreNull() throws {
        // The app has no setup screen, so this is the ordinary state of a
        // lifter early in a conversation — and "Full gym, Intermediate" here
        // would be the server asserting something nobody ever said.
        let report = try context(
            profile: fixtureProfile(
                experience: nil, availableEquipment: nil))
        let lifter = try #require(report["lifter"])

        #expect(lifter.objectValue?["experience"] == .null)
        #expect(lifter.objectValue?["availableEquipment"] == .null)
    }

    @Test("The facts nobody has stated are named, not left to be noticed one null at a time")
    func unstatedFactsAreNamed() throws {
        let report = try context(
            profile: fixtureProfile(
                experience: nil, availableEquipment: nil))

        #expect(report["lifter"]?["unstated"] == ["equipment", "experience"])
        let note = try #require(report["note"]?.stringValue)
        #expect(note.contains("equipment"))
        #expect(note.contains(ToolCatalog.updateProfile))
    }

    @Test("A lifter who has stated everything is not nagged about it")
    func fullyStatedProfileNamesNothing() throws {
        #expect(try context()["lifter"]?["unstated"] == .array([]))
    }

    @Test("It stays small enough to carry every turn")
    func staysCompact() throws {
        let rendered = try context().prettyEncoded()

        #expect(rendered.count < 8_000, "actual: \(rendered.count) characters")
    }
}
