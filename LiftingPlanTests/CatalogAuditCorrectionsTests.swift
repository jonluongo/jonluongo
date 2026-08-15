import Testing
import Foundation
@testable import LiftingPlan

/// Guards on the two data corrections the equipment/mechanic audit produced,
/// in both directions.
///
/// `CatalogIntegrityTests` already guards *over*-correction — that running and
/// hiking stay `.bodyweight` when the cycling and swimming entries are fixed.
/// These guard *under*-correction: that an exercise a lifter cannot perform
/// empty-handed never ships as `.bodyweight`, and that the cardio entries
/// carry a mechanic derived from one rule rather than per-row patches.
/// Depends on: the bundled `ExerciseCatalog` only.
@Suite("Catalog audit corrections")
struct CatalogAuditCorrectionsTests {

    private func loaded() throws -> ExerciseCatalog {
        try ExerciseCatalog.bundled()
    }

    /// `.bodyweight` is the tier a lifter with nothing gets
    /// (`EquipmentAccess.bodyweightTier` is exactly `[.bodyweight]`), so it is
    /// a promise: hand this to someone in a hotel room and they can do it.
    /// The generator's `defaultEquipment` breaks that promise silently — a
    /// slug no equipment keyword matches ships as `bodyweight` whether or not
    /// the movement needs anything.
    ///
    /// The line drawn here: an exercise is `.bodyweight` only if it needs
    /// nothing but the lifter's body, the ground or a wall, and a bar to hang
    /// from. The bar is existing precedent, not a new concession —
    /// `bodyweightCoverage` requires a `.bodyweight` option for
    /// `.verticalPull`, so unloaded pull-ups and chin-ups are already modeled
    /// that way. What fails the line is a discrete object the lifter must
    /// have to hand: added load, a rope, a box, a bench, or a step at bench
    /// height. That is why `weighted-pull-ups` is listed while `pull-ups` is
    /// not, and why `bulgarian-split-squat` (rear foot at bench height) is
    /// listed while `front-foot-elevated-split-squat` (front foot on a curb
    /// or a book) is not.
    @Test("An exercise needing an object to perform is never tagged bodyweight")
    func equipmentRequiringMovementsAreNotBodyweight() throws {
        let catalog = try loaded()
        let slugs = [
            // Added external load, by definition.
            "weighted-pull-ups",
            // A rope, a plyo box, a bench, a step.
            "jump-rope", "box-jump", "bodyweight-box-squat",
            "bulgarian-split-squat", "bench-dips", "single-leg-step-down",
            "b-stance-hip-thrust", "single-leg-hip-thrust",
            // A decline bench: there is no flat-ground execution of these.
            "decline-crunch", "decline-sit-up", "decline-push-up",
        ]
        for slug in slugs {
            let exercise = try #require(catalog.exercise(id: ExerciseID(rawValue: slug)),
                                        "\(slug) missing from catalog")
            #expect(exercise.equipment != .bodyweight,
                    "\(slug) equipment is \(exercise.equipment)")
        }
    }

    /// Class-level guard rather than a list, so it also catches the next
    /// entry nobody thought about. A slug whose own name says the movement is
    /// loaded cannot be equipment-free, whatever the keyword tables derive:
    /// `weighted-pull-ups` shipped as `.bodyweight` for exactly this reason —
    /// no equipment keyword matched it, so it took the default.
    @Test("A slug that names added load is never tagged bodyweight")
    func loadedVariantsAreNeverBodyweight() throws {
        let loadTokens: Set<String> = ["weighted", "loaded"]
        let offenders = try loaded().all.filter { exercise in
            let tokens = Set(exercise.id.rawValue.split(separator: "-").map(String.init))
            return !tokens.isDisjoint(with: loadTokens) && exercise.equipment == .bodyweight
        }
        #expect(offenders.isEmpty,
                "loaded variants tagged bodyweight: \(offenders.map(\.id.rawValue).sorted())")
    }

    /// Running, swimming, rowing, cycling, and climbing are whole-body,
    /// multi-joint work — `compound` by the same joint-count definition
    /// `Mechanic` uses everywhere else. Calling a freestyle swim `isolation`
    /// was not a debatable classification, it was the absence of one: `cardio`
    /// was missing from `compoundPatterns`, so all 34 cardio entries derived
    /// `isolation` and three of them were hand-patched back to `compound` one
    /// row at a time.
    ///
    /// This asserts the rule, not the three rows: every cardio entry, so the
    /// next one added inherits the right answer instead of needing its own
    /// patch.
    @Test("Every cardio exercise is compound, not isolation")
    func cardioIsAlwaysCompound() throws {
        let cardio = try loaded().all.filter { $0.category == .cardio }
        #expect(cardio.count >= 30, "only \(cardio.count) cardio entries found")
        let offenders = cardio.filter { $0.mechanic == .isolation }
        #expect(offenders.isEmpty,
                "cardio tagged isolation: \(offenders.map(\.id.rawValue).sorted())")
    }
}
