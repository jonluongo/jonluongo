import Testing
import Foundation
@testable import LiftingPlan
import LiftingKit

/// A store that keeps rest choices in a dictionary, so the rules can be checked
/// without a defaults database that outlives the test that wrote to it.
@MainActor
private final class InMemoryRestStore: RestPreferenceStoring {

    var timersEnabled = true
    var rests: [ExerciseID: LifterRest] = [:]

    func loadTimersEnabled() -> Bool { timersEnabled }
    func save(timersEnabled: Bool) { self.timersEnabled = timersEnabled }
    func loadRests() -> [ExerciseID: LifterRest] { rests }

    func save(_ rest: LifterRest, for id: ExerciseID) {
        if case .asPrescribed = rest {
            rests.removeValue(forKey: id)
        } else {
            rests[id] = rest
        }
    }
}

private let bench = ExerciseID(rawValue: "barbell-bench-press")
private let squat = ExerciseID(rawValue: "barbell-back-squat")

/// What the clock runs is the lifter's to say; what the plan prescribed is
/// Claude's, and the two are never the same number by accident.
@MainActor
@Suite("Lifter rest")
struct LifterRestTests {

    @Test("Saying nothing runs exactly what the plan prescribed")
    func silenceFollowsThePlan() {
        #expect(LifterRest.asPrescribed.runningSeconds(prescribed: 180, timersEnabled: true) == 180)
        #expect(LifterRest.asPrescribed.runningSeconds(prescribed: nil, timersEnabled: true) == nil)
    }

    @Test("A length of his own runs instead of the prescribed one")
    func ownLengthRuns() {
        #expect(LifterRest.seconds(120).runningSeconds(prescribed: 180, timersEnabled: true) == 120)
        #expect(LifterRest.seconds(120).runningSeconds(prescribed: nil, timersEnabled: true) == 120)
    }

    @Test("Off on this exercise runs nothing, whatever the plan prescribed")
    func offRunsNothing() {
        #expect(LifterRest.off.runningSeconds(prescribed: 180, timersEnabled: true) == nil)
    }

    @Test("Off everywhere runs nothing, whatever any exercise says")
    func masterSwitchWins() {
        #expect(LifterRest.asPrescribed.runningSeconds(prescribed: 180, timersEnabled: false) == nil)
        #expect(LifterRest.seconds(120).runningSeconds(prescribed: 180, timersEnabled: false) == nil)
    }

    @Test("A clock dialled to zero runs nothing, and a prescribed zero is passed through")
    func zeroes() {
        // Nothing can count down from zero. A zero Claude wrote is still his to
        // write, and it is `RestTimerModel` that declines to run it.
        #expect(LifterRest.seconds(0).runningSeconds(prescribed: 180, timersEnabled: true) == nil)
        #expect(LifterRest.asPrescribed.runningSeconds(prescribed: 0, timersEnabled: true) == 0)
    }
}

@MainActor
@Suite("Rest preferences")
struct RestPreferenceTests {

    @Test("An exercise nobody has touched follows the plan")
    func untouchedFollowsThePlan() {
        let preferences = RestPreferences(store: InMemoryRestStore())
        #expect(preferences.rest(for: bench) == .asPrescribed)
        #expect(preferences.runningSeconds(prescribed: 180, for: bench) == 180)
    }

    @Test("A choice is kept per exercise, not for the session or for all of them")
    func choiceIsPerExercise() {
        let preferences = RestPreferences(store: InMemoryRestStore())
        preferences.setRest(.seconds(120), for: bench)
        #expect(preferences.runningSeconds(prescribed: 180, for: bench) == 120)
        #expect(preferences.runningSeconds(prescribed: 180, for: squat) == 180)
    }

    @Test("Going back to the plan forgets the choice rather than freezing today's number")
    func backToThePlanForgets() {
        // The difference matters the week Claude changes the rest: a stored 180
        // would keep running 180 forever, while no entry at all follows him.
        let store = InMemoryRestStore()
        let preferences = RestPreferences(store: store)
        preferences.setRest(.seconds(120), for: bench)
        preferences.setRest(.asPrescribed, for: bench)
        #expect(store.rests[bench] == nil)
        #expect(preferences.runningSeconds(prescribed: 240, for: bench) == 240)
    }

    @Test("The master switch is on until the lifter turns it off, and is remembered")
    func masterSwitchPersists() {
        let store = InMemoryRestStore()
        let preferences = RestPreferences(store: store)
        #expect(preferences.timersEnabled)
        preferences.setTimersEnabled(false)
        #expect(store.timersEnabled == false)
        #expect(RestPreferences(store: store).timersEnabled == false)
        #expect(preferences.runningSeconds(prescribed: 180, for: bench) == nil)
    }

    @Test("Choices survive a relaunch, off included")
    func choicesSurviveRelaunch() throws {
        let name = "rest-preferences-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let first = RestPreferences(store: UserDefaultsRestStore(defaults: defaults))
        first.setRest(.seconds(150), for: bench)
        first.setRest(.off, for: squat)
        first.setTimersEnabled(false)

        let second = RestPreferences(store: UserDefaultsRestStore(defaults: defaults))
        #expect(second.rest(for: bench) == .seconds(150))
        #expect(second.rest(for: squat) == .off)
        #expect(second.timersEnabled == false)
    }

    @Test("A stored value this build cannot read means following the plan")
    func unreadableValueFollowsThePlan() {
        // The one answer that cannot be wrong: the exercise goes back to
        // whatever Claude prescribed rather than to a number nobody chose.
        #expect(LifterRest(storedValue: "forever") == .asPrescribed)
        #expect(LifterRest(storedValue: "off") == .off)
        #expect(LifterRest(storedValue: "90") == .seconds(90))
    }
}
