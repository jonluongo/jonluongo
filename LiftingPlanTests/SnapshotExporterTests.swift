import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

@Suite("Snapshot exporter")
struct SnapshotExporterTests {

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    /// Inserts one plan holding one week, one day, one exercise, and one set,
    /// and returns the context so a test can export from it.
    private func contextWithOneLoggedSet(
        load: Mass? = Mass(value: 135, unit: .pounds),
        restSeconds: Int? = 180
    ) throws -> ModelContext {
        let context = try context()
        // Built the way `PlanImporter` builds one: a block that states no
        // document identity cannot be read back as the document it came from,
        // and the exporter reports it as absent rather than inventing one.
        let plan = TrainingPlan(
            title: "Strength block", goal: "Bigger bench", generatedAt: Date(),
            weekCount: 4, weekdays: [.monday], durationMinutes: 60,
            catalogVersion: 5, sourceDocumentID: UUID()
        )
        let week = TrainingWeek(ordinal: 1, label: "Accumulation")
        let day = WorkoutDay(weekday: .monday, focus: "Push", durationMinutes: 60)
        let exercise = PlannedExercise(
            exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
            displayName: "Barbell Bench Press", order: 0, targetSets: 3,
            repRange: "5", suggestedLoad: Mass(value: 100, unit: .kilograms),
            restSeconds: restSeconds, tempo: "3-0-1-0", notes: "Pause the last rep"
        )
        exercise.loggedSets = [
            LoggedSet(setIndex: 0, load: load, reps: 5, isCompleted: true)
        ]
        day.exercises = [exercise]
        week.days = [day]
        plan.weeks = [week]
        context.insert(plan)
        try context.saveOrThrow()
        return context
    }

    private func firstExercise(
        in snapshot: TrainingSnapshot
    ) throws -> PlanDocumentExercise {
        try #require(snapshot.firstPrescribedExercise)
    }

    // MARK: - Absence is normal

    @Test("An empty store exports a valid snapshot rather than throwing")
    func emptyStoreExports() throws {
        let snapshot = try SnapshotExporter.export(from: try context(), catalogVersion: 5)

        #expect(snapshot.version == TrainingSnapshot.currentVersion)
        #expect(snapshot.catalogVersion == 5)
        #expect(snapshot.profile == nil)
        #expect(snapshot.bodyMetrics.isEmpty)
        #expect(snapshot.baselines.isEmpty)
        #expect(snapshot.routines.isEmpty)
    }

    @Test("An empty snapshot still encodes and decodes")
    func emptyStoreSnapshotRoundTrips() throws {
        let snapshot = try SnapshotExporter.export(from: try context(), catalogVersion: 5)
        let data = try TrainingSnapshot.makeEncoder().encode(snapshot)
        let decoded = try TrainingSnapshot.makeDecoder()
            .decode(TrainingSnapshot.self, from: data)
        #expect(decoded.routines.isEmpty)
    }

    @Test("An unprescribed rest is exported as absent, not as a number")
    func absentRestStaysAbsent() throws {
        let context = try contextWithOneLoggedSet(restSeconds: nil)
        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)
        #expect(try firstExercise(in: snapshot).restSeconds == nil)
    }

    @Test("A bodyweight set is exported with no load rather than a zero load")
    func bodyweightSetHasNoLoad() throws {
        let context = try contextWithOneLoggedSet(load: nil)
        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)
        let set = try #require(snapshot.firstLoggedSet)
        #expect(set.load == nil)
        #expect(set.reps == 5)
    }

    // MARK: - Mass survives as entered

    @Test("A logged set exports the unit it was entered in, not a canonical one")
    func loggedSetKeepsEnteredUnit() throws {
        let context = try contextWithOneLoggedSet(load: Mass(value: 135, unit: .pounds))
        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)
        let load = try #require(snapshot.firstLoggedSet?.load)

        #expect(load.unit == .pounds)
        #expect(load.value == 135)
        // `Mass` compares exactly on representation, so converting anywhere in
        // the export path fails this.
        #expect(load == Mass(value: 135, unit: .pounds))
        #expect(load != Mass(value: 135, unit: .pounds).converted(to: .kilograms))
    }

    @Test("Units survive the whole export-encode-decode path independently")
    func unitsSurviveEncoding() throws {
        let context = try contextWithOneLoggedSet(load: Mass(value: 135, unit: .pounds))
        let profile = UserProfile(bodyweight: Mass(value: 182, unit: .pounds))
        context.insert(profile)
        context.insert(StrengthBaseline(
            exerciseID: ExerciseID(rawValue: "barbell-back-squat"),
            load: Mass(value: 100, unit: .kilograms), reps: 5
        ))
        try context.saveOrThrow()

        let data = try TrainingSnapshot.makeEncoder()
            .encode(try SnapshotExporter.export(from: context, catalogVersion: 5))
        let decoded = try TrainingSnapshot.makeDecoder()
            .decode(TrainingSnapshot.self, from: data)

        let exercise = try firstExercise(in: decoded)
        #expect(decoded.firstLoggedSet?.load == Mass(value: 135, unit: .pounds))
        // Prescribed in kilograms while the set was logged in pounds: one
        // snapshot carries both, each as written.
        #expect(exercise.suggestedLoad == Mass(value: 100, unit: .kilograms))
        #expect(decoded.profile?.bodyweight == Mass(value: 182, unit: .pounds))
        #expect(decoded.baselines.first?.load == Mass(value: 100, unit: .kilograms))
    }

    // MARK: - The profile

    @Test("The profile is exported with its stated facts intact")
    func profileIsExported() throws {
        let context = try context()
        context.insert(UserProfile(
            displayUnit: .kilograms, experience: .advanced,
            ownedEquipment: [.dumbbell, .plate], goal: "Get stronger", constraints: "Left shoulder hurts overhead",
            bodyweight: Mass(value: 82, unit: .kilograms),
            avoidedPatterns: [.verticalPress],
            avoidedExercises: [ExerciseID(rawValue: "barbell-upright-row")],
            preferredWeekdays: [.monday, .thursday], preferredDurationMinutes: 45
        ))
        try context.saveOrThrow()

        let profile = try #require(
            try SnapshotExporter.export(from: context, catalogVersion: 5).profile
        )
        #expect(profile.displayUnit == .kilograms)
        #expect(profile.experience == .advanced)
        #expect(profile.goal == "Get stronger")
        #expect(profile.constraints == "Left shoulder hurts overhead")
        #expect(profile.avoidedPatterns == [.verticalPress])
        #expect(profile.avoidedExercises == [ExerciseID(rawValue: "barbell-upright-row")])
        #expect(profile.preferredWeekdays == [.monday, .thursday])
        #expect(profile.preferredDurationMinutes == 45)
        // What he owns, and bodyweight besides — a push-up needs none of it.
        #expect(profile.availableEquipment.map(Set.init) == [.dumbbell, .plate, .bodyweight])
    }

    @Test("The last applied profile update is carried, so the writer can tell what has landed")
    func appliedUpdateIsCarried() throws {
        // Without it the Mac cannot tell an update still waiting in the folder
        // from one already taken in, and would re-impose facts on every write.
        let identity = UUID()
        let context = try context()
        context.insert(UserProfile(appliedProfileUpdateID: identity))
        try context.saveOrThrow()

        let profile = try #require(
            try SnapshotExporter.export(from: context, catalogVersion: 5).profile
        )
        #expect(profile.appliedProfileUpdateID == identity)
    }

    @Test("A profile nobody has filled in exports as unknown, not as a plausible default")
    func unstatedProfileFactsExportAsAbsent() throws {
        // The app asks him nothing, so this is what a real first launch looks
        // like. Exporting "Full gym, Intermediate" here would hand Claude an
        // assertion about the lifter that no one ever made, indistinguishable
        // from one he did.
        let context = try context()
        context.insert(UserProfile())
        try context.saveOrThrow()

        let profile = try #require(
            try SnapshotExporter.export(from: context, catalogVersion: 5).profile
        )
        #expect(profile.experience == nil)
        // Not an empty list: that would say he can perform nothing.
        #expect(profile.availableEquipment == nil)
        #expect(profile.goal.isEmpty)
        #expect(profile.preferredWeekdays.isEmpty)
        #expect(profile.preferredDurationMinutes == nil)
    }

    @Test("A movement pattern this build does not know survives the export")
    func unknownAvoidedPatternSurvives() throws {
        let unknown = MovementPattern(rawValue: "anti-rotation")
        #expect(!unknown.isKnown)

        let context = try context()
        context.insert(UserProfile(avoidedPatterns: [unknown]))
        try context.saveOrThrow()

        let data = try TrainingSnapshot.makeEncoder()
            .encode(try SnapshotExporter.export(from: context, catalogVersion: 5))
        let decoded = try TrainingSnapshot.makeDecoder()
            .decode(TrainingSnapshot.self, from: data)
        #expect(decoded.profile?.avoidedPatterns == [unknown])
    }

    @Test("When duplicate profiles exist, the most recently updated one is exported")
    func mostRecentProfileWins() throws {
        let context = try context()
        let older = UserProfile(goal: "Older")
        older.updatedAt = Date(timeIntervalSince1970: 1_000)
        let newer = UserProfile(goal: "Newer")
        newer.updatedAt = Date(timeIntervalSince1970: 2_000)
        context.insert(older)
        context.insert(newer)
        try context.saveOrThrow()

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)
        #expect(snapshot.profile?.goal == "Newer")
    }

    // MARK: - Plans and logged sets

    @Test("A plan exports with its weeks, days, exercises, and logged sets")
    func planExportsWholeGraph() throws {
        let context = try contextWithOneLoggedSet()
        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 7)

        let plan = try #require(snapshot.firstDocument)
        #expect(plan.title == "Strength block")
        // Derived from the weeks it states rather than stored beside them, so
        // there is no second number to disagree with the document.
        #expect(plan.blockCount == 1)
        #expect(plan.blocks.first?.days.map(\.weekday) == [.monday])
        // The plan keeps the catalog version it was built against, which need
        // not be the one the snapshot was produced under.
        #expect(plan.catalogVersion == 5)
        #expect(snapshot.catalogVersion == 7)

        let exercise = try firstExercise(in: snapshot)
        #expect(exercise.exerciseID == ExerciseID(rawValue: "barbell-bench-press"))
        #expect(exercise.displayName == "Barbell Bench Press")
        #expect(exercise.sets == 3)
        #expect(exercise.repRange == "5")
        #expect(exercise.restSeconds == 180)
        #expect(exercise.tempo == "3-0-1-0")
        #expect(exercise.notes == "Pause the last rep")

        let set = try #require(snapshot.firstLoggedSet)
        #expect(set.reps == 5)
        #expect(set.isCompleted)
        // The row names where it sits, which is how the prescription above is
        // found again.
        #expect(set.blockOrdinal == 1)
        #expect(set.weekday == .monday)
        #expect(set.exerciseOrder == 0)
        #expect(set.routineID == plan.id)
    }

    @Test("Warmup and unfinished sets are exported too, labelled rather than dropped")
    func warmupAndUnfinishedSetsAreKept() throws {
        let context = try context()
        let exercise = PlannedExercise(
            exerciseID: ExerciseID(rawValue: "barbell-back-squat"),
            displayName: "Barbell Back Squat", order: 0, targetSets: 3, repRange: "5"
        )
        exercise.loggedSets = [
            LoggedSet(setIndex: 0, reps: 5, isCompleted: true, isWarmup: true),
            LoggedSet(setIndex: 1, reps: 5, isCompleted: true),
            LoggedSet(setIndex: 2, reps: 0, isCompleted: false),
        ]
        let day = WorkoutDay(weekday: .monday)
        day.exercises = [exercise]
        let week = TrainingWeek(ordinal: 1)
        week.days = [day]
        let plan = TrainingPlan(
            title: "Block", generatedAt: Date(), catalogVersion: 5,
            sourceDocumentID: UUID())
        plan.weeks = [week]
        context.insert(plan)
        try context.saveOrThrow()

        let sets = try SnapshotExporter.export(from: context, catalogVersion: 5).log
            .sorted { $0.setIndex < $1.setIndex }
        #expect(sets.count == 3)
        #expect(sets.map(\.setIndex) == [0, 1, 2])
        #expect(sets.map(\.isWarmup) == [true, false, false])
        #expect(sets.map(\.isCompleted) == [true, true, false])
    }

    @Test("Weeks, days, exercises, and sets export in order")
    func graphExportsInOrder() throws {
        let context = try context()
        let plan = TrainingPlan(
            title: "Block", generatedAt: Date(), catalogVersion: 5,
            sourceDocumentID: UUID())
        let firstWeek = TrainingWeek(ordinal: 1)
        let secondWeek = TrainingWeek(ordinal: 2, label: "Deload", isDeload: true)
        let thursday = WorkoutDay(weekday: .thursday, focus: "Pull")
        let monday = WorkoutDay(weekday: .monday, focus: "Push")
        let second = PlannedExercise(
            exerciseID: ExerciseID(rawValue: "dumbbell-fly"),
            displayName: "Dumbbell Fly", order: 1
        )
        let first = PlannedExercise(
            exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
            displayName: "Barbell Bench Press", order: 0
        )
        // Stamped out of order on purpose, and stated rather than left to the
        // clock: the log is a series, so its order is the order the work
        // happened in, not the order the rows were built in.
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        first.loggedSets = [
            LoggedSet(setIndex: 1, reps: 5, completedAt: started.addingTimeInterval(180)),
            LoggedSet(setIndex: 0, reps: 5, completedAt: started),
        ]
        monday.exercises = [second, first]
        firstWeek.days = [thursday, monday]
        plan.weeks = [secondWeek, firstWeek]
        context.insert(plan)
        try context.saveOrThrow()

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)
        let exportedPlan = try #require(snapshot.firstDocument)
        // A week's ordinal is its position in the list now, so the order *is*
        // the ordinal: the deload week stated second comes second.
        #expect(exportedPlan.blocks.count == 2)
        #expect(exportedPlan.blocks.map(\.isDeload) == [false, true])
        #expect(exportedPlan.blocks.first?.days.map(\.weekday) == [.monday, .thursday])
        #expect(try firstExercise(in: snapshot).displayName == "Barbell Bench Press")
        #expect(snapshot.log.map(\.setIndex) == [0, 1], "oldest first")
    }

    @Test("Body metrics and baselines export oldest first")
    func metricsAndBaselinesExportInOrder() throws {
        let context = try context()
        context.insert(BodyMetric(
            date: Date(timeIntervalSince1970: 2_000),
            bodyweight: Mass(value: 183, unit: .pounds)
        ))
        context.insert(BodyMetric(
            date: Date(timeIntervalSince1970: 1_000),
            bodyweight: Mass(value: 182, unit: .pounds)
        ))
        try context.saveOrThrow()

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)
        #expect(snapshot.bodyMetrics.map(\.bodyweight?.value) == [182, 183])
    }
}
