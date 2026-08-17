import Foundation
import Testing
import LiftingKit
@testable import LiftingMCPKit

/// Writing a plan whose exercises are grouped.
///
/// The tool surface is the only place Claude can learn this shape from, so what
/// it accepts and what it refuses is the contract these pin: a group lands as a
/// group, an exercise inside one cannot carry a rest, and a day of ungrouped
/// exercises is written exactly as it always was.
@Suite("write_plan with grouped exercises")
struct SupersetPlanTests {

    private func plan(_ arguments: JSONValue) throws -> (ToolOutcome, InMemoryDocuments) {
        let documents = InMemoryDocuments(snapshot: fixtureSnapshot())
        let outcome = try makeRunner(documents: documents)
            .call(ToolCatalog.writePlan, arguments: arguments)
        return (outcome, documents)
    }

    /// A day with one ungrouped press and a superset of curl and pulldown.
    private static let supersetDay: JSONValue = [
        "weekday": "monday", "focus": "Upper",
        "exercises": [
            [
                "exerciseID": "barbell-bench-press", "displayName": "Barbell Bench Press",
                "sets": 4, "repRange": "6-8", "restSeconds": 180,
            ],
            [
                "restSeconds": 90,
                "group": [
                    [
                        "exerciseID": "barbell-curl", "displayName": "Barbell Curl",
                        "sets": 3, "repRange": "12-15",
                    ],
                    [
                        "exerciseID": "lat-pulldown", "displayName": "Lat Pulldown",
                        "sets": 3, "repRange": "12-15",
                    ],
                ],
            ],
        ],
    ]

    private func day(of document: PlanDocument?) throws -> PlanDocumentDay {
        let document = try #require(document)
        return try #require(document.everyDay.first)
    }

    // MARK: - A group lands as a group

    @Test("A superset lands in the plan as one group with its own rest")
    func supersetIsWritten() throws {
        let (outcome, documents) = try plan(["days": [Self.supersetDay]])
        #expect(outcome.failureMessage == nil)

        let day = try day(of: documents.lastWrittenPlan)
        #expect(day.entries.count == 2)
        let group = try #require(day.entries.last?.group)
        #expect(group.exercises.map(\.exerciseID.rawValue) == ["barbell-curl", "lat-pulldown"])
        #expect(group.restSeconds == 90)
        #expect(group.exercises.allSatisfy { $0.restSeconds == nil })
    }

    @Test("A tri-set is written as a group of three; nothing here is limited to pairs")
    func triSetIsWritten() throws {
        let (outcome, documents) = try plan([
            "days": [[
                "weekday": "friday",
                "exercises": [[
                    "restSeconds": 120,
                    "group": [
                        ["exerciseID": "push-up", "displayName": "Push Up", "sets": 3],
                        ["exerciseID": "barbell-curl", "displayName": "Barbell Curl", "sets": 3],
                        ["exerciseID": "lat-pulldown", "displayName": "Lat Pulldown", "sets": 3],
                    ],
                ]],
            ]],
        ])
        #expect(outcome.failureMessage == nil)

        let day = try day(of: documents.lastWrittenPlan)
        #expect(day.entries.count == 1)
        #expect(day.entries.first?.group?.exercises.count == 3)
        #expect(day.exercises.count == 3, "every movement is still one of the day's exercises")
    }

    @Test("The report says a group came back as a group, not as loose exercises")
    func groupIsReportedAsAGroup() throws {
        let (outcome, _) = try plan(["days": [Self.supersetDay]])
        let report = try #require(outcome.report)
        let entries = try #require(
            report["plan"]?["weeks"]?[0]?["days"]?[0]?["exercises"]?.arrayValue)

        #expect(entries.count == 2)
        #expect(entries[0]["group"] == nil, "the ungrouped press is reported as it always was")
        let group = try #require(entries[1]["group"]?.arrayValue)
        #expect(group.count == 2)
        #expect(group[0]["exerciseID"]?.stringValue == "barbell-curl")
        #expect(entries[1]["restSeconds"]?.intValue == 90)
        #expect(report["exerciseCount"]?.intValue == 3, "a grouped movement is still a movement")
    }

    @Test("A grouped plan survives the file, read back with the phone's own decoder")
    func groupedPlanSurvivesTheFile() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "superset-plan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let documents = DocumentFolder(directory: folder)
        let outcome = try makeRunner(documents: documents)
            .call(ToolCatalog.writePlan, arguments: ["days": [Self.supersetDay]])
        #expect(outcome.failureMessage == nil)

        let day = try day(of: try documents.readPlan())
        let group = try #require(day.entries.last?.group)
        #expect(group.restSeconds == 90)
        #expect(group.exercises.map(\.displayName) == ["Barbell Curl", "Lat Pulldown"])
        #expect(day.entries.first?.group == nil)
    }

    // MARK: - What it refuses

    @Test("An exercise inside a group stating its own rest fails the call by name")
    func restInsideAGroupFailsTheCall() throws {
        let (outcome, documents) = try plan([
            "days": [[
                "weekday": "monday",
                "exercises": [[
                    "restSeconds": 90,
                    "group": [
                        [
                            "exerciseID": "barbell-curl", "displayName": "Barbell Curl",
                            "sets": 3, "restSeconds": 45,
                        ],
                        ["exerciseID": "lat-pulldown", "displayName": "Lat Pulldown", "sets": 3],
                    ],
                ]],
            ]],
        ])
        let message = try #require(outcome.failureMessage)

        #expect(message.contains("'restSeconds'"))
        #expect(message.contains("Barbell Curl"))
        #expect(message.contains("after the round"))
        #expect(documents.lastWrittenPlan == nil, "nothing was written")
    }

    @Test("A group of one fails the call and writes nothing")
    func groupOfOneFailsTheCall() throws {
        let (outcome, documents) = try plan([
            "days": [[
                "weekday": "monday",
                "exercises": [[
                    "group": [
                        ["exerciseID": "barbell-curl", "displayName": "Barbell Curl", "sets": 3]
                    ],
                ]],
            ]],
        ])
        let message = try #require(outcome.failureMessage)

        #expect(message.contains("two or more"))
        #expect(documents.lastWrittenPlan == nil)
    }

    @Test("An exercise the catalog does not have is caught inside a group too")
    func unknownExerciseInsideAGroupFailsTheCall() throws {
        let (outcome, documents) = try plan([
            "days": [[
                "weekday": "monday",
                "exercises": [[
                    "restSeconds": 90,
                    "group": [
                        ["exerciseID": "barbell-curl", "displayName": "Barbell Curl", "sets": 3],
                        ["exerciseID": "invented-fly", "displayName": "Invented Fly", "sets": 3],
                    ],
                ]],
            ]],
        ])
        let message = try #require(outcome.failureMessage)

        #expect(message.contains("'invented-fly'"))
        #expect(documents.lastWrittenPlan == nil)
    }

    // MARK: - The common case is untouched

    @Test("A day of ungrouped exercises is written exactly as it always was")
    func ungroupedDayIsUnchanged() throws {
        let (outcome, documents) = try plan([
            "days": [[
                "weekday": "monday",
                "exercises": [[
                    "exerciseID": "barbell-squat", "displayName": "Barbell Squat",
                    "sets": 5, "repRange": "5", "restSeconds": 240,
                ]],
            ]],
        ])
        #expect(outcome.failureMessage == nil)

        let day = try day(of: documents.lastWrittenPlan)
        #expect(day.entries.count == 1)
        #expect(day.entries.first?.group == nil)
        #expect(day.exercises.first?.restSeconds == 240, "its own rest is still its own")

        let report = try #require(outcome.report)
        let entry = try #require(report["plan"]?["weeks"]?[0]?["days"]?[0]?["exercises"]?[0])
        #expect(entry["exerciseID"]?.stringValue == "barbell-squat")
        #expect(entry["group"] == nil)
    }

    // MARK: - The schema says so

    @Test("The tool surface states the group shape, so it can be learned from the tool alone")
    func schemaAdvertisesGroups() throws {
        let definition = ToolCatalog.writePlanDefinition
        #expect(definition.description.contains("\"group\""))
        #expect(definition.description.contains("after the round"))

        let weeks = try #require(definition.inputSchema["properties"]?["weeks"])
        let week = try #require(weeks["items"])
        let days = try #require(week["properties"]?["days"])
        let day = try #require(days["items"])
        let entries = try #require(day["properties"]?["exercises"])
        let entry = try #require(entries["items"])
        let shapes = try #require(entry["anyOf"]?.arrayValue)
        #expect(shapes.count == 2)
        #expect(shapes[1]["properties"]?["group"] != nil)
        #expect(shapes[1]["properties"]?["restSeconds"] != nil)
    }
}
