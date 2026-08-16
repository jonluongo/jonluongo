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
        #expect(lifter["preferredWeekdays"] == ["Monday", "Thursday"])
        #expect(lifter["preferredDurationMinutes"] == 60)
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
        #expect(block["weekCount"] == 4)
        #expect(block["weekdays"] == ["Monday", "Thursday"])
        #expect(block["durationMinutes"] == 60)
        #expect(block["weeksLogged"] == 1)
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
