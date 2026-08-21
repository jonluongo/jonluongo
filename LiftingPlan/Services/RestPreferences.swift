import Foundation
import Observation
import LiftingKit

/// What the user has asked his own clock to do between sets of one exercise.
///
/// **What it does.** Names the three answers there are — follow the plan, run a
/// length of his own, or run nothing — as one value, so nothing downstream has
/// to read a duration beside a flag and decide which of the two wins.
/// `.asPrescribed` is the *absence* of a choice rather than a copy of the
/// prescribed number: an exercise he has never touched keeps following Claude's
/// rest even after Claude changes it.
///
/// **How it is used.** Read out of `RestPreferences` for an exercise and asked
/// `runningSeconds(prescribed:)`, which answers the only number that matters —
/// what the countdown counts down, or `nil` when nothing runs.
/// Nothing here writes to a prescription, and nothing here can: it never sees
/// the store.
///
/// **What it depends on.** Foundation. Deliberately *not* in LiftingKit: a
/// timer preference is not part of the vocabulary the phone and the coach
/// share, and nothing that leaves this device may carry it.
enum UserRest: Equatable, Sendable {

    /// Whatever the plan prescribed, including nothing.
    case asPrescribed

    /// A length of the user's own, in seconds.
    case seconds(Int)

    /// What the clock actually runs, given what the plan prescribed for this
    /// exercise, or `nil` when nothing runs.
    ///
    /// A zero is nothing: a clock cannot count down from it, and reporting it
    /// as a rest to run would put a countdown on screen that finishes before it
    /// is drawn. A zero the *plan* prescribed is passed through untouched — that
    /// is Claude's number to state, and `RestTimerModel` declines it on its own.
    func runningSeconds(prescribed: Int?) -> Int? {
        switch self {
        case .asPrescribed: return prescribed
        case .seconds(let seconds): return seconds > 0 ? seconds : nil
        }
    }

    /// How the choice is written down, or `nil` for `.asPrescribed`, which is
    /// stored as nothing at all — the user having said nothing and the user
    /// having said "as prescribed" are the same state and must not become two.
    var storedValue: String? {
        switch self {
        case .asPrescribed: nil
        case .seconds(let seconds): String(seconds)
        }
    }

    /// The inverse of `storedValue`. An unreadable value reads as no choice,
    /// which is the one answer that cannot be wrong: the exercise goes back to
    /// following the plan.
    init(storedValue: String) {
        if let seconds = Int(storedValue) {
            self = .seconds(seconds)
        } else {
            self = .asPrescribed
        }
    }
}

/// Where a user's rest choices are kept between sessions.
///
/// **What it does.** Loads and saves the per-exercise choices, and nothing else
/// — every question about what those choices *mean* belongs to `UserRest`.
///
/// **How it is used.** `RestPreferences` holds one. `UserDefaultsRestStore` is
/// the real one; a dictionary-backed fake stands in for it in tests, which is
/// what lets the persistence rules be checked without a simulator's defaults
/// database leaking between runs.
///
/// **What it depends on.** `ExerciseID` from LiftingKit, and `UserRest`.
@MainActor
protocol RestPreferenceStoring {
    func loadRests() -> [ExerciseID: UserRest]
    func save(_ rest: UserRest, for id: ExerciseID)
    /// Whether the clock runs at all, or `nil` when nobody has said. Absent
    /// means on: a user who has never touched the switch has a working timer.
    func loadClockIsOn() -> Bool?
    func saveClockIsOn(_ isOn: Bool)
    /// Every exercise the retired per-exercise *off* was stored against, so the
    /// switch it becomes can start where he left it. Read once, at launch.
    func exercisesSilencedByAnOlderBuild() -> [ExerciseID]
}

/// The real store: `UserDefaults`, on this device only.
///
/// **What it does.** Keeps each exercise's choice under its slug.
///
/// **How it is used.** Constructed by `RestPreferences` with no argument in the
/// app; a test hands it its own suite.
///
/// **Why not SwiftData.** `PlannedExercise` and `LoggedSet` are exported in the
/// snapshot Claude reads back. A timer preference stored beside them is one
/// refactor away from being reported as a training fact he prescribed — the bug
/// this design exists to prevent. `UserDefaults` cannot reach `SnapshotExporter`
/// at all, so the guarantee is structural rather than a matter of remembering.
///
/// **What it depends on.** Foundation's `UserDefaults`.
@MainActor
struct UserDefaultsRestStore: RestPreferenceStoring {

    private let defaults: UserDefaults
    private static let restPrefix = "rest.exercise."
    private static let clockKey = "rest.clockIsOn"
    /// What an older build wrote against an exercise to silence just that one.
    private static let retiredOffValue = "off"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadRests() -> [ExerciseID: UserRest] {
        var rests: [ExerciseID: UserRest] = [:]
        for (key, value) in defaults.dictionaryRepresentation()
        where key.hasPrefix(Self.restPrefix) {
            guard let stored = value as? String else { continue }
            guard stored != Self.retiredOffValue else { continue }
            let slug = String(key.dropFirst(Self.restPrefix.count))
            rests[ExerciseID(rawValue: slug)] = UserRest(storedValue: stored)
        }
        return rests
    }

    func loadClockIsOn() -> Bool? {
        defaults.object(forKey: Self.clockKey) as? Bool
    }

    func saveClockIsOn(_ isOn: Bool) {
        defaults.set(isOn, forKey: Self.clockKey)
    }

    func exercisesSilencedByAnOlderBuild() -> [ExerciseID] {
        defaults.dictionaryRepresentation()
            .filter { $0.key.hasPrefix(Self.restPrefix) && $0.value as? String == Self.retiredOffValue }
            .map { ExerciseID(rawValue: String($0.key.dropFirst(Self.restPrefix.count))) }
    }

    func save(_ rest: UserRest, for id: ExerciseID) {
        let key = Self.restPrefix + id.rawValue
        guard let stored = rest.storedValue else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(stored, forKey: key)
    }
}

/// The user's own rest clock: how long it runs on each exercise.
///
/// **What it does.** Holds the one thing the prescription cannot hold — what
/// the user wants his clock to do — and answers the logging screen's only
/// question about it: how many seconds to run when a set is ticked. It is kept
/// per exercise because rest is prescribed per exercise, and persisted because
/// a user who wants two minutes on bench wants two minutes on bench next
/// Tuesday as well; making him dial it again every session is the annoyance
/// that produced this screen's redesign.
///
/// **The switch is one switch, and it is the only preference in the app.**
/// Silencing was per exercise once, on the reasoning that rest is prescribed per
/// exercise — but a user reaching for the switch is not saying *not on the
/// bench press*, he is saying *not today*, and having to say it again on the
/// next movement is the app making him repeat himself. `isClockOn` is app-wide;
/// what stays per exercise is the *length*, which is the thing that genuinely
/// differs between movements.
///
/// **How it is used.** One instance, made at launch and put in the environment.
/// `ActiveWorkoutView` asks `runningSeconds(prescribed:for:)` when a set is
/// ticked, and `ExerciseRestSheet` writes a choice.
///
/// **What it depends on.** `RestPreferenceStoring`, and `ExerciseID` from
/// LiftingKit. It never touches the model context, so no edit here can reach
/// `PlannedExercise.restSeconds` — the number Claude wrote and reads back.
@Observable
@MainActor
final class RestPreferences {

    /// Only the exercises he has said something about. An absent entry is
    /// `.asPrescribed`.
    private(set) var rests: [ExerciseID: UserRest]

    /// Whether the countdown runs at all. On until he says otherwise.
    private(set) var isClockOn: Bool

    private let store: any RestPreferenceStoring

    init(store: any RestPreferenceStoring = UserDefaultsRestStore()) {
        self.store = store
        rests = store.loadRests()
        // A user who silenced any exercise under the older build was saying
        // the clock should not run; the switch starts where he left it rather
        // than coming back on and going off in his pocket.
        isClockOn = store.loadClockIsOn()
            ?? store.exercisesSilencedByAnOlderBuild().isEmpty
    }

    /// Turns the countdown on or off everywhere.
    func setClockIsOn(_ isOn: Bool) {
        isClockOn = isOn
        store.saveClockIsOn(isOn)
    }

    /// What this exercise's clock has been told to do — `.asPrescribed` when
    /// nobody has told it anything.
    func rest(for id: ExerciseID) -> UserRest {
        rests[id] ?? .asPrescribed
    }

    /// Records a choice, and drops the entry entirely when it goes back to
    /// following the plan.
    func setRest(_ rest: UserRest, for id: ExerciseID) {
        if case .asPrescribed = rest {
            rests.removeValue(forKey: id)
        } else {
            rests[id] = rest
        }
        store.save(rest, for: id)
    }

    /// The seconds the countdown should run after a set of this exercise, or
    /// `nil` when none should.
    func runningSeconds(prescribed: Int?, for id: ExerciseID) -> Int? {
        guard isClockOn else { return nil }
        return rest(for: id).runningSeconds(prescribed: prescribed)
    }
}
