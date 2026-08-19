import Testing
import Foundation
@testable import LiftingPlan
import LiftingKit

/// A store that keeps rest choices in a dictionary, so the rules can be checked
/// without a defaults database that outlives the test that wrote to it.
@MainActor
private final class InMemoryRestStore: RestPreferenceStoring {

    var rests: [ExerciseID: LifterRest] = [:]

    func loadRests() -> [ExerciseID: LifterRest] { rests }

    func save(_ rest: LifterRest, for id: ExerciseID) {
        if case .asPrescribed = rest {
            rests.removeValue(forKey: id)
        } else {
            rests[id] = rest
        }
    }

    var clockIsOn: Bool?
    /// What an older build silenced one exercise at a time with.
    var silencedByAnOlderBuild: [ExerciseID] = []

    func loadClockIsOn() -> Bool? { clockIsOn }
    func saveClockIsOn(_ isOn: Bool) { clockIsOn = isOn }
    func exercisesSilencedByAnOlderBuild() -> [ExerciseID] { silencedByAnOlderBuild }
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
        #expect(LifterRest.asPrescribed.runningSeconds(prescribed: 180) == 180)
        #expect(LifterRest.asPrescribed.runningSeconds(prescribed: nil) == nil)
    }

    @Test("A length of his own runs instead of the prescribed one")
    func ownLengthRuns() {
        #expect(LifterRest.seconds(120).runningSeconds(prescribed: 180) == 120)
        #expect(LifterRest.seconds(120).runningSeconds(prescribed: nil) == 120)
    }

    @Test("A clock dialled to zero runs nothing, and a prescribed zero is passed through")
    func zeroes() {
        // Nothing can count down from zero. A zero Claude wrote is still his to
        // write, and it is `RestTimerModel` that declines to run it.
        #expect(LifterRest.seconds(0).runningSeconds(prescribed: 180) == nil)
        #expect(LifterRest.asPrescribed.runningSeconds(prescribed: 0) == 0)
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

    @Test("The switch is one switch: turning it off stops every countdown")
    func theSwitchIsUniversal() {
        // Jon: turning it off on one exercise should do it universally. A
        // lifter reaching for it is not saying *not on the bench press*, he is
        // saying *not today*.
        let preferences = RestPreferences(store: InMemoryRestStore())
        preferences.setRest(.seconds(120), for: bench)

        preferences.setClockIsOn(false)

        #expect(preferences.runningSeconds(prescribed: 180, for: bench) == nil)
        #expect(preferences.runningSeconds(prescribed: 180, for: squat) == nil)
    }

    @Test("Switching it back on gives every exercise its own length again")
    func lengthsSurviveTheSwitch() {
        // The switch silences; it does not forget. A lifter who turns the clock
        // off for a session and back on the next one should not have to dial
        // two minutes on the bench press again.
        let preferences = RestPreferences(store: InMemoryRestStore())
        preferences.setRest(.seconds(120), for: bench)
        preferences.setClockIsOn(false)

        preferences.setClockIsOn(true)

        #expect(preferences.runningSeconds(prescribed: 180, for: bench) == 120)
        #expect(preferences.runningSeconds(prescribed: 180, for: squat) == 180)
    }

    @Test("A lifter who has never touched the switch has a working clock")
    func theClockStartsOn() {
        #expect(RestPreferences(store: InMemoryRestStore()).isClockOn)
    }

    @Test("A lifter who silenced an exercise under the older build opens with it off")
    func silenceCarriesAcross() {
        // The old build said *off* one exercise at a time. He meant the clock
        // should not run; the switch starts where he left it rather than coming
        // back on in his pocket.
        let store = InMemoryRestStore()
        store.silencedByAnOlderBuild = [bench]

        #expect(!RestPreferences(store: store).isClockOn)
    }

    @Test("Choices and the switch both survive a relaunch")
    func choicesSurviveRelaunch() throws {
        let name = "rest-preferences-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let first = RestPreferences(store: UserDefaultsRestStore(defaults: defaults))
        first.setRest(.seconds(150), for: bench)
        first.setClockIsOn(false)

        let second = RestPreferences(store: UserDefaultsRestStore(defaults: defaults))
        #expect(second.rest(for: bench) == .seconds(150))
        #expect(!second.isClockOn)
    }

    @Test("A stored value this build cannot read means following the plan")
    func unreadableValueFollowsThePlan() {
        // The one answer that cannot be wrong: the exercise goes back to
        // whatever Claude prescribed rather than to a number nobody chose. An
        // `off` written by the older build reads the same way — it has become
        // the switch, and is not a length.
        #expect(LifterRest(storedValue: "forever") == .asPrescribed)
        #expect(LifterRest(storedValue: "off") == .asPrescribed)
        #expect(LifterRest(storedValue: "90") == .seconds(90))
    }
}
