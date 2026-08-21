import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// Which block the app opens on, and what is behind it.
///
/// **The front page answers one question — *what am I doing*.** It listed every
/// block ever prescribed, so that answer moved further down the screen every
/// week. The split is here rather than in the view because *current* has to mean
/// one thing in the app: the list and the history are two readings of it, and
/// two definitions would eventually disagree about which block a session is in.
@MainActor
@Suite("The current block, and the ones behind it")
struct BlockHistoryTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let day: TimeInterval = 86_400

    /// A store holding `blocks` blocks of `perBlock` sessions each.
    private func store(blocks: Int, perBlock: Int = 2) throws -> ModelContext {
        try StoreFixture.imported(blocks: blocks, sessionsPerBlock: perBlock)
    }

    /// Adds a block of `count` sessions at `ordinal`, since a plan may now state
    /// only one block at a time.
    private func addBlock(_ ordinal: Int, sessions count: Int, to context: ModelContext) throws {
        try PlanImporter.import(
            StoreFixture.plan(block: ordinal, sessions: count),
            into: context, catalog: try StoreFixture.catalog())
    }

    /// Marks a session trained, `dayOffset` days after the fixed instant.
    private func train(_ session: Session, dayOffset: Int) {
        session.finishedAt = Self.instant.addingTimeInterval(Double(dayOffset) * Self.day)
    }

    // MARK: - Which block is current

    @Test("The current block is the one holding the earliest unfinished session")
    func theCurrentBlockIsWhereTheWorkIs() throws {
        let context = try store(blocks: 1)
        try addBlock(2, sessions: 2, to: context)
        let all = try StoreFixture.sessions(in: context)
        for session in all where session.blockOrdinal == 1 { train(session, dayOffset: 0) }

        #expect(BlockHistory.currentOrdinal(of: all) == 2)
        #expect(BlockHistory.current(of: all).allSatisfy { $0.blockOrdinal == 2 })
    }

    @Test("With everything finished, the last block is still the current one")
    func nothingIsBehindHimUntilTheCoachWritesMore() throws {
        // A user who has finished everything is still *on* the block he just
        // finished. Reporting it as history would empty the front page and put
        // the block he trained this morning behind a button.
        let context = try store(blocks: 1)
        let all = try StoreFixture.sessions(in: context)
        for session in all { train(session, dayOffset: 0) }

        #expect(BlockHistory.currentOrdinal(of: all) == 1)
        #expect(BlockHistory.past(of: all).isEmpty)
    }

    @Test("An empty record has no current block and no history")
    func anEmptyRecordIsNeither() throws {
        let context = try StoreFixture.context()
        let all = try StoreFixture.sessions(in: context)

        #expect(BlockHistory.currentOrdinal(of: all) == nil)
        #expect(BlockHistory.current(of: all).isEmpty)
        #expect(BlockHistory.past(of: all).isEmpty)
    }

    // MARK: - What is behind him

    @Test("History holds every earlier block, newest first")
    func historyReadsBackwards() throws {
        let context = try store(blocks: 1)
        try addBlock(2, sessions: 2, to: context)
        try addBlock(3, sessions: 2, to: context)
        let all = try StoreFixture.sessions(in: context)
        for session in all where session.blockOrdinal < 3 { train(session, dayOffset: 0) }

        #expect(BlockHistory.past(of: all).map(\.ordinal) == [2, 1],
                "anything looked up reads backwards")
    }

    @Test("The current block is never in history")
    func theCurrentBlockIsNotBehindHim() throws {
        let context = try store(blocks: 1)
        try addBlock(2, sessions: 2, to: context)
        let all = try StoreFixture.sessions(in: context)
        for session in all where session.blockOrdinal == 1 { train(session, dayOffset: 0) }

        let ordinals = BlockHistory.past(of: all).map(\.ordinal)
        #expect(!ordinals.contains(2))
        #expect(ordinals == [1])
    }

    // MARK: - What a finished block is called

    @Test("A block is headed by the days it was trained over")
    func aBlockIsDatedFromItsRecord() throws {
        let context = try store(blocks: 1, perBlock: 3)
        let all = try StoreFixture.sessions(in: context)
        train(all[0], dayOffset: 0)
        train(all[1], dayOffset: 3)
        train(all[2], dayOffset: 21)

        let range = try #require(BlockHistory.dateRange(of: all))
        #expect(range.contains("–"), "a range, joined by an en dash")
        #expect(range.hasPrefix(Self.instant.formatted(.dateTime.month(.abbreviated).day())))
    }

    @Test("A block trained in one day says one day, not a range to itself")
    func oneDayIsOneDate() throws {
        let context = try store(blocks: 1, perBlock: 2)
        let all = try StoreFixture.sessions(in: context)
        for session in all { train(session, dayOffset: 0) }

        let range = try #require(BlockHistory.dateRange(of: all))
        #expect(!range.contains("–"), "\(range)")
    }

    @Test("A block that recorded nothing has no date, and cannot reach history")
    func anUntrainedBlockHasNoDate() throws {
        // The case that does not arise: a block nothing was logged against is
        // not behind him, it is in front of him. Asserted so the two halves
        // cannot drift — if `past(of:)` ever admitted one, this says what the
        // heading would have to fall back to.
        let context = try store(blocks: 1)
        let all = try StoreFixture.sessions(in: context)

        #expect(BlockHistory.dateRange(of: all) == nil)
        #expect(BlockHistory.past(of: all).isEmpty)
    }

    @Test("A session finished without a set ticked still dates its block")
    func finishingCountsAsTraining() throws {
        // `finishedAt` alone is evidence: he went through the session. A block
        // containing it happened, and a heading reading *no date* would be the
        // app calling that a non-event.
        let context = try store(blocks: 1, perBlock: 1)
        let all = try StoreFixture.sessions(in: context)
        train(all[0], dayOffset: 5)

        #expect(BlockHistory.dateRange(of: all) != nil)
    }
}
