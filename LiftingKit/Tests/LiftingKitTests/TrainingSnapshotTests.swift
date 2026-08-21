import Testing
import Foundation
@testable import LiftingKit

/// What the record carries to the coach, and what it refuses.
///
/// **The suite this replaced was mostly about the user.** It asserted a
/// profile's goal, experience, constraints, equipment, avoid lists, bodyweight
/// series and strength baselines survived the wire — nine fields that were
/// display-only in the app and are now prose in `ACCOUNT.md`, where he can be
/// described in sentences rather than columns. What is left is the training:
/// what was asked for, what was done, and when this was written.
@Suite("The record on the wire")
struct TrainingSnapshotTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let later = Date(timeIntervalSince1970: 1_700_003_600)
    private let bench = ExerciseID(rawValue: "barbell-bench-press")

    private func session(block: Int = 1, ordinal: Int = 1, finished: Date? = nil)
        -> SnapshotSession {
        SnapshotSession(
            prescription: PlanDocumentSession(
                blockOrdinal: block, ordinal: ordinal, focus: "Push", icon: .strength,
                entries: [.exercise(PlanDocumentExercise(
                    exerciseID: bench, displayName: "Barbell Bench Press", restSeconds: 180,
                    sets: [PlanDocumentSet(
                        target: .repetitions(low: 5, high: 6),
                        load: Mass(value: 100, unit: .kilograms))]))]),
            finishedAt: finished, generatedAt: Self.instant, sourceDocumentID: UUID())
    }

    private func performance(
        source: PerformanceSource = .logged, block: Int? = 1, ordinal: Int? = 1
    ) -> SnapshotPerformedExercise {
        SnapshotPerformedExercise(
            exerciseID: bench, occurredAt: Self.instant, source: source,
            blockOrdinal: block, sessionOrdinal: ordinal, userNote: "Felt heavy.",
            sets: [SnapshotPerformedSet(
                setIndex: 0, load: Mass(value: 225, unit: .pounds), reps: 5,
                completedAt: Self.instant)])
    }

    private func snapshot(
        sessions: [SnapshotSession] = [], performances: [SnapshotPerformedExercise] = []
    ) -> TrainingSnapshot {
        TrainingSnapshot(
            exportedAt: Self.later, catalogVersion: 5,
            sessions: sessions, performances: performances)
    }

    private func roundTrip(_ snapshot: TrainingSnapshot) throws -> TrainingSnapshot {
        let data = try TrainingSnapshot.makeEncoder().encode(snapshot)
        return try TrainingSnapshot.makeDecoder().decode(TrainingSnapshot.self, from: data)
    }

    private func decoded(_ json: String) throws -> TrainingSnapshot {
        try TrainingSnapshot.makeDecoder().decode(TrainingSnapshot.self, from: Data(json.utf8))
    }

    // MARK: - The envelope

    @Test("A snapshot says when it was written, and that reaches the reader")
    func exportedAtSurvives() throws {
        // The failure this guards against arrives looking like a fact: a coach
        // told a block holds four sessions when it holds nine. A date does not
        // stop the export going stale; it stops a stale read being convincing.
        let read = try roundTrip(snapshot())
        #expect(read.exportedAt == Self.later)
        #expect(read.version == 7)
        #expect(read.catalogVersion == 5)
    }

    @Test("An empty record is a record, not a failure")
    func anEmptyRecordDecodes() throws {
        let read = try roundTrip(snapshot())
        #expect(read.sessions.isEmpty)
        #expect(read.performances.isEmpty)
    }

    // MARK: - What was asked for

    @Test("A session carries the prescription itself rather than a second description of it")
    func sessionsCarryTheDocument() throws {
        let read = try roundTrip(snapshot(sessions: [session()]))
        let carried = try #require(read.sessions.first)

        #expect(carried.prescription.focus == "Push")
        #expect(carried.prescription.icon == .strength)
        let set = try #require(carried.prescription.exercises.first?.sets.first)
        #expect(set.target == .repetitions(low: 5, high: 6))
        #expect(set.load == Mass(value: 100, unit: .kilograms))
    }

    @Test("A finished session says so, and an unfinished one says nothing")
    func finishedSessionsAreMarked() throws {
        let read = try roundTrip(snapshot(sessions: [
            session(ordinal: 1, finished: Self.instant), session(ordinal: 2),
        ]))
        #expect(read.sessions(inBlock: 1).map(\.isFinished) == [true, false])
    }

    @Test("Blocks are reported in order, however the sessions arrive")
    func blocksAreOrdered() throws {
        let read = try roundTrip(snapshot(sessions: [
            session(block: 3, ordinal: 1), session(block: 1, ordinal: 2),
            session(block: 1, ordinal: 1),
        ]))
        #expect(read.blockOrdinals == [1, 3])
        #expect(read.sessions(inBlock: 1).map(\.ordinal) == [1, 2])
    }

    // MARK: - What was done

    @Test("A performance carries its own sets rather than being one row per set")
    func performancesHoldTheirSets() throws {
        // The log used to be flat, restating the plan, block, weekday, focus and
        // prescription on every row, because nothing sat at the grain the
        // question is asked at.
        let read = try roundTrip(snapshot(performances: [performance()]))
        let performed = try #require(read.performances.first)

        #expect(performed.exerciseID == bench)
        #expect(performed.sets.count == 1)
        #expect(performed.sets.first?.reps == 5)
        #expect(performed.userNote == "Felt heavy.")
    }

    @Test("A performance says which session it belongs to")
    func performancesCarryTheirCoordinates() throws {
        let read = try roundTrip(snapshot(performances: [performance(block: 2, ordinal: 3)]))
        let performed = try #require(read.performances.first)
        #expect(performed.blockOrdinal == 2)
        #expect(performed.sessionOrdinal == 3)
    }

    @Test("A stated baseline is a performance with no session behind it")
    func aStatedBaselineHasNoCoordinates() throws {
        // It was its own table, saying the same thing in the same shape, so
        // every history report had to answer twice.
        let read = try roundTrip(snapshot(performances: [
            performance(source: .stated, block: nil, ordinal: nil)
        ]))
        let stated = try #require(read.performances.first)

        #expect(stated.source == .stated)
        #expect(stated.blockOrdinal == nil)
        #expect(stated.sessionOrdinal == nil)
        #expect(stated.sets.first?.reps == 5, "he still did it; nobody watched")
    }

    @Test("Performances of one lift read oldest first")
    func historyIsOrdered() throws {
        let older = SnapshotPerformedExercise(exerciseID: bench, occurredAt: Self.instant)
        let newer = SnapshotPerformedExercise(exerciseID: bench, occurredAt: Self.later)
        let other = SnapshotPerformedExercise(
            exerciseID: ExerciseID(rawValue: "barbell-squat"), occurredAt: Self.later)

        let read = try roundTrip(snapshot(performances: [newer, other, older]))
        #expect(read.performances(of: bench).map(\.occurredAt) == [Self.instant, Self.later])
    }

    // MARK: - Measures never mix

    @Test("A hold, a carry and a count stay in their own fields")
    func measuresNeverMix() throws {
        let sets = [
            SnapshotPerformedSet(setIndex: 0, reps: 8, completedAt: Self.instant),
            SnapshotPerformedSet(setIndex: 1, durationSeconds: 45, completedAt: Self.instant),
            SnapshotPerformedSet(
                setIndex: 2, distance: Distance(value: 40, unit: .metres),
                completedAt: Self.instant),
        ]
        let read = try roundTrip(snapshot(performances: [
            SnapshotPerformedExercise(exerciseID: bench, occurredAt: Self.instant, sets: sets)
        ]))
        let performed = try #require(read.performances.first)

        #expect(performed.sets.map(\.reps) == [8, nil, nil])
        #expect(performed.sets.map(\.durationSeconds) == [nil, 45, nil])
        #expect(performed.sets.map { $0.distance?.value } == [nil, nil, 40])
    }

    @Test("A set ticked without a count says nothing rather than saying none")
    func absentRepsAreNotZero() throws {
        // `reps` used to be a non-optional Int, so a set prescribed as a range
        // and ticked without a number reached the coach as a completed working
        // set at 185 lb by 0.
        let read = try roundTrip(snapshot(performances: [
            SnapshotPerformedExercise(
                exerciseID: bench, occurredAt: Self.instant,
                sets: [SnapshotPerformedSet(
                    setIndex: 0, load: Mass(value: 185, unit: .pounds),
                    completedAt: Self.instant)])
        ]))
        #expect(try #require(read.performances.first).sets.first?.reps == nil)
    }

    @Test("A load keeps the unit it was recorded in, on both sides of the record")
    func loadsAreNeverConverted() throws {
        // The prescription is in kilograms and the set was logged in pounds.
        // A snapshot that canonicalized would misreport what was lifted.
        let read = try roundTrip(snapshot(sessions: [session()], performances: [performance()]))
        let prescribed = try #require(
            read.sessions.first?.prescription.exercises.first?.sets.first?.load)
        let performed = try #require(read.performances.first?.sets.first?.load)

        #expect(prescribed.unit == .kilograms)
        #expect(performed.unit == .pounds)
    }

    @Test("Warm-ups are told apart from work on the record side too")
    func warmupsAreDistinguished() throws {
        let read = try roundTrip(snapshot(performances: [
            SnapshotPerformedExercise(
                exerciseID: bench, occurredAt: Self.instant,
                sets: [
                    SnapshotPerformedSet(setIndex: 0, isWarmup: true, completedAt: Self.instant),
                    SnapshotPerformedSet(setIndex: 1, reps: 5, completedAt: Self.instant),
                ])
        ]))
        #expect(try #require(read.performances.first).workingSets.count == 1)
    }

    // MARK: - Refusal, in both directions

    @Test("A snapshot from either direction of skew is refused whole")
    func skewIsRefusedBothWays() throws {
        // A plan is an archive and an older one must read forever. A snapshot is
        // a cache the phone rewrites whenever the record changes, so an old one
        // is a stale file rather than history — and reading it half-way would
        // report a user who has trained less than he has.
        for stated in [6, 8] {
            let error = #expect(throws: DocumentRefusal.self, "\(stated)") {
                try decoded("""
                    {"version": \(stated), "exportedAt": "2023-11-14T22:13:20Z",
                     "catalogVersion": 5}
                    """)
            }
            let message = try #require(error?.errorDescription)
            #expect(message.contains("\(stated)"))
            #expect(message.contains("7"))
        }
    }

    @Test("A key this format does not have is refused, naming it")
    func anUnknownKeyIsRefused() throws {
        let error = #expect(throws: DocumentRefusal.self) {
            try decoded("""
                {"version": 7, "exportedAt": "2023-11-14T22:13:20Z",
                 "catalogVersion": 5, "profile": {"goal": "Get strong"}}
                """)
        }
        #expect(try #require(error?.errorDescription).contains("profile"),
                "who he is lives in ACCOUNT.md, not on this wire")
    }
}
