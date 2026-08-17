import Foundation
import Observation
import LiftingKit

/// What the lifter has asked his own clock to do between sets of one exercise.
///
/// **What it does.** Names the three answers there are — follow the plan, run a
/// length of his own, or run nothing — as one value, so nothing downstream has
/// to read a duration beside a flag and decide which of the two wins.
/// `.asPrescribed` is the *absence* of a choice rather than a copy of the
/// prescribed number: an exercise he has never touched keeps following Claude's
/// rest even after Claude changes it.
///
/// **How it is used.** Read out of `RestPreferences` for an exercise and asked
/// `runningSeconds(prescribed:timersEnabled:)`, which answers the only number
/// that matters — what the countdown counts down, or `nil` when nothing runs.
/// Nothing here writes to a prescription, and nothing here can: it never sees
/// the store.
///
/// **What it depends on.** Foundation. Deliberately *not* in LiftingKit: a
/// timer preference is not part of the vocabulary the phone and the coach
/// share, and nothing that leaves this device may carry it.
enum LifterRest: Equatable, Sendable {

    /// Whatever the plan prescribed, including nothing.
    case asPrescribed

    /// A length of the lifter's own, in seconds.
    case seconds(Int)

    /// No countdown on this exercise.
    case off

    /// What the clock actually runs, given what the plan prescribed for this
    /// exercise, or `nil` when nothing runs.
    ///
    /// A zero is nothing: a clock cannot count down from it, and reporting it
    /// as a rest to run would put a countdown on screen that finishes before it
    /// is drawn. A zero the *plan* prescribed is passed through untouched — that
    /// is Claude's number to state, and `RestTimerModel` declines it on its own.
    func runningSeconds(prescribed: Int?, timersEnabled: Bool) -> Int? {
        guard timersEnabled else { return nil }
        switch self {
        case .asPrescribed: return prescribed
        case .seconds(let seconds): return seconds > 0 ? seconds : nil
        case .off: return nil
        }
    }

    /// How the choice is written down, or `nil` for `.asPrescribed`, which is
    /// stored as nothing at all — the lifter having said nothing and the lifter
    /// having said "as prescribed" are the same state and must not become two.
    var storedValue: String? {
        switch self {
        case .asPrescribed: nil
        case .off: "off"
        case .seconds(let seconds): String(seconds)
        }
    }

    /// The inverse of `storedValue`. An unreadable value reads as no choice,
    /// which is the one answer that cannot be wrong: the exercise goes back to
    /// following the plan.
    init(storedValue: String) {
        if storedValue == "off" {
            self = .off
        } else if let seconds = Int(storedValue) {
            self = .seconds(seconds)
        } else {
            self = .asPrescribed
        }
    }
}

/// Where a lifter's rest choices are kept between sessions.
///
/// **What it does.** Loads and saves the master switch and the per-exercise
/// choices, and nothing else — every question about what those choices *mean*
/// belongs to `LifterRest`.
///
/// **How it is used.** `RestPreferences` holds one. `UserDefaultsRestStore` is
/// the real one; a dictionary-backed fake stands in for it in tests, which is
/// what lets the persistence rules be checked without a simulator's defaults
/// database leaking between runs.
///
/// **What it depends on.** `ExerciseID` from LiftingKit, and `LifterRest`.
@MainActor
protocol RestPreferenceStoring {
    func loadTimersEnabled() -> Bool
    func save(timersEnabled: Bool)
    func loadRests() -> [ExerciseID: LifterRest]
    func save(_ rest: LifterRest, for id: ExerciseID)
}

/// The real store: `UserDefaults`, on this device only.
///
/// **What it does.** Keeps the master switch under one key and each exercise's
/// choice under its slug.
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
    private static let timersEnabledKey = "rest.timersEnabled"
    private static let restPrefix = "rest.exercise."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// On unless the lifter has switched it off. An unset key is not `false`:
    /// `bool(forKey:)` cannot tell those apart, so the object is asked for.
    func loadTimersEnabled() -> Bool {
        defaults.object(forKey: Self.timersEnabledKey) as? Bool ?? true
    }

    func save(timersEnabled: Bool) {
        defaults.set(timersEnabled, forKey: Self.timersEnabledKey)
    }

    func loadRests() -> [ExerciseID: LifterRest] {
        var rests: [ExerciseID: LifterRest] = [:]
        for (key, value) in defaults.dictionaryRepresentation()
        where key.hasPrefix(Self.restPrefix) {
            guard let stored = value as? String else { continue }
            let slug = String(key.dropFirst(Self.restPrefix.count))
            rests[ExerciseID(rawValue: slug)] = LifterRest(storedValue: stored)
        }
        return rests
    }

    func save(_ rest: LifterRest, for id: ExerciseID) {
        let key = Self.restPrefix + id.rawValue
        guard let stored = rest.storedValue else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(stored, forKey: key)
    }
}

/// The lifter's own rest clock: on or off everywhere, and how long on each
/// exercise.
///
/// **What it does.** Holds the one thing the prescription cannot hold — what
/// the lifter wants his clock to do — and answers the logging screen's only
/// question about it: how many seconds to run when a set is ticked. It is kept
/// per exercise because rest is prescribed per exercise, and persisted because
/// a lifter who wants two minutes on bench wants two minutes on bench next
/// Tuesday as well; making him dial it again every session is the annoyance
/// that produced this screen's redesign.
///
/// **How it is used.** One instance, made at launch and put in the environment.
/// `ActiveWorkoutView` asks `runningSeconds(prescribed:for:)` when a set is
/// ticked, `ExerciseRestSheet` writes a choice, and `AccountView` flips the
/// master switch.
///
/// **What it depends on.** `RestPreferenceStoring`, and `ExerciseID` from
/// LiftingKit. It never touches the model context, so no edit here can reach
/// `PlannedExercise.restSeconds` — the number Claude wrote and reads back.
@Observable
@MainActor
final class RestPreferences {

    /// Whether any countdown runs at all. Off is the lifter saying he does not
    /// want a rest timer; what Claude prescribed is still shown either way,
    /// because that is a training fact and not a feature of the app.
    private(set) var timersEnabled: Bool

    /// Only the exercises he has said something about. An absent entry is
    /// `.asPrescribed`.
    private(set) var rests: [ExerciseID: LifterRest]

    private let store: any RestPreferenceStoring

    init(store: any RestPreferenceStoring = UserDefaultsRestStore()) {
        self.store = store
        timersEnabled = store.loadTimersEnabled()
        rests = store.loadRests()
    }

    func setTimersEnabled(_ enabled: Bool) {
        guard enabled != timersEnabled else { return }
        timersEnabled = enabled
        store.save(timersEnabled: enabled)
    }

    /// What this exercise's clock has been told to do — `.asPrescribed` when
    /// nobody has told it anything.
    func rest(for id: ExerciseID) -> LifterRest {
        rests[id] ?? .asPrescribed
    }

    /// Records a choice, and drops the entry entirely when it goes back to
    /// following the plan.
    func setRest(_ rest: LifterRest, for id: ExerciseID) {
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
        rest(for: id).runningSeconds(prescribed: prescribed, timersEnabled: timersEnabled)
    }
}
