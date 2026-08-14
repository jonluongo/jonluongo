import Testing
import Foundation
@testable import LiftingPlan

@Suite("Catalog integrity")
struct CatalogIntegrityTests {

    /// Loads the bundled catalog, failing the test loudly if it cannot be read.
    /// Deliberately not `try?` — a missing or malformed catalog must surface as
    /// the real error, not as an empty result.
    private func loaded() throws -> ExerciseCatalog {
        try ExerciseCatalog.bundled()
    }

    @Test("The catalog holds exactly the 412 MoveKit exercises")
    func count() throws {
        #expect(try loaded().all.count == 412)
    }

    @Test("Every id is unique")
    func idsUnique() throws {
        let all = try loaded().all
        #expect(Set(all.map(\.id)).count == all.count)
    }

    @Test("Every entry has a display name")
    func namesPresent() throws {
        for exercise in try loaded().all {
            #expect(!exercise.displayName.trimmingCharacters(in: .whitespaces).isEmpty,
                    "\(exercise.id) has no display name")
        }
    }

    @Test("Every entry has at least one primary muscle")
    func primaryMusclesPresent() throws {
        for exercise in try loaded().all {
            #expect(!exercise.primaryMuscles.isEmpty, "\(exercise.id) has no primary muscle")
        }
    }

    @Test("Every taxonomy value in the catalog is one this build recognizes")
    func taxonomiesRecognized() throws {
        for exercise in try loaded().all {
            #expect(exercise.equipment.isKnown, "\(exercise.id): unknown equipment \(exercise.equipment)")
            #expect(exercise.pattern.isKnown, "\(exercise.id): unknown pattern \(exercise.pattern)")
            #expect(exercise.category.isKnown, "\(exercise.id): unknown category \(exercise.category)")
            for muscle in exercise.primaryMuscles + exercise.secondaryMuscles {
                #expect(muscle.isKnown, "\(exercise.id): unknown muscle \(muscle)")
            }
        }
    }

    @Test("A muscle is never both primary and secondary for one exercise")
    func musclesDoNotOverlap() throws {
        for exercise in try loaded().all {
            #expect(Set(exercise.primaryMuscles).isDisjoint(with: Set(exercise.secondaryMuscles)),
                    "\(exercise.id) repeats a muscle")
        }
    }

    @Test("Enough of the catalog is resistance training to build plans from")
    func resistanceCoverage() throws {
        let resistance = try loaded().all.filter(\.isResistanceTraining)
        #expect(resistance.count > 300, "only \(resistance.count) resistance exercises")
    }

    @Test("Every resistance movement pattern has at least one bodyweight option")
    func bodyweightCoverage() throws {
        let loaded = try loaded()
        for pattern in [MovementPattern.squat, .hinge, .horizontalPress, .verticalPull] {
            let filter = ExerciseFilter(equipment: [.bodyweight], patterns: [pattern])
            #expect(!loaded.exercises(matching: filter).isEmpty,
                    "no bodyweight option for \(pattern)")
        }
    }

    @Test("Every catalog entry resolves to itself by display name")
    func everyEntryResolves() throws {
        let loaded = try loaded()
        let resolver = ExerciseResolver(catalog: loaded)
        for exercise in loaded.all {
            let resolved = resolver.resolve(exercise.displayName)
            #expect(resolved?.id == exercise.id, "\(exercise.id) did not resolve to itself")
        }
    }

    /// No alias string may be claimed by more than one entry. A shared alias
    /// is exactly how the resolver's `.alias` tier — a confidence callers
    /// treat as safe to persist — can point at the wrong exercise; this is
    /// the same class of bug that let "upright barbell row" resolve to a
    /// dumbbell exercise and "decline barbell bench press" collide with
    /// "barbell-incline-bench-press"'s bad enrichment.
    @Test("No alias is claimed by more than one catalog entry")
    func aliasesAreUnique() throws {
        var owner: [String: ExerciseID] = [:]
        for exercise in try loaded().all {
            for alias in exercise.aliases {
                let key = alias.lowercased()
                if let existing = owner[key] {
                    Issue.record(
                        "alias \"\(alias)\" is claimed by both \(existing) and \(exercise.id)")
                } else {
                    owner[key] = exercise.id
                }
            }
        }
    }

    /// If a slug names a muscle, its primary muscles must not contradict it.
    ///
    /// Matching is on hyphen-delimited tokens, not substrings, so "lat" does
    /// not fire inside "plate" or "lateral" and "trap" does not fire inside
    /// unrelated tokens. A handful of slugs still need explicit exclusion
    /// because the token means something other than the target muscle there:
    /// "trap-bar-deadlift" names its equipment (a hex bar), not the traps;
    /// the "chest-supported" rows describe what a lifter leans against, not
    /// what the row trains; "behind-the-neck-press" is a shoulder press
    /// performed behind the neck, not a neck exercise. Scoped to these
    /// unambiguous cases rather than every substring so the check stays
    /// reliable rather than flaky.
    @Test("A slug that names a muscle does not contradict its own primary muscles")
    func slugMuscleAgreement() throws {
        let expectations: [String: MuscleGroup] = [
            "abduction": .abductors, "adduction": .adductors, "calf": .calves,
            "tricep": .triceps, "bicep": .biceps, "hamstring": .hamstrings,
            "quad": .quadriceps, "glute": .glutes, "chest": .chest,
            "shoulder": .shoulders, "lat": .lats, "trap": .traps,
            "forearm": .forearms, "neck": .neck,
        ]
        let excluded: Set<String> = [
            "trap-bar-deadlift",
            "chest-supported-dumbbell-row", "chest-supported-t-bar-row",
            "behind-the-neck-press",
        ]

        for exercise in try loaded().all where !excluded.contains(exercise.id.rawValue) {
            let tokens = Set(exercise.id.rawValue.split(separator: "-").map(String.init))
            for (token, muscle) in expectations where tokens.contains(token) {
                #expect(exercise.primaryMuscles.contains(muscle),
                        "\(exercise.id) names \"\(token)\" but primary muscles are \(exercise.primaryMuscles)")
            }
        }
    }

    @Test("Compound resistance exercises name the muscles they work beyond the prime mover")
    func secondaryMusclesPresent() throws {
        let catalog = try ExerciseCatalog.bundled()
        let needsSecondary = catalog.all.filter {
            $0.isResistanceTraining && $0.mechanic == .compound
        }
        let missing = needsSecondary.filter { $0.secondaryMuscles.isEmpty }
        #expect(missing.isEmpty,
                "compound exercises with no secondary muscles: \(missing.map(\.id.rawValue).sorted())")
    }

    @Test("Known exercises name the specific muscles a lifter would expect")
    func secondaryMusclesAreCorrect() throws {
        let catalog = try ExerciseCatalog.bundled()

        func secondaries(_ id: String) throws -> Set<MuscleGroup> {
            let exercise = try #require(catalog.exercise(id: ExerciseID(rawValue: id)),
                                        "\(id) missing from catalog")
            return Set(exercise.secondaryMuscles)
        }

        // A bench press works triceps and front delts. This is the case that
        // motivated the whole task.
        #expect(try secondaries("barbell-bench-press").contains(.triceps))
        #expect(try secondaries("barbell-bench-press").contains(.shoulders))
        // A pulldown works biceps.
        #expect(try secondaries("lat-pulldown").contains(.biceps))
        // A squat works glutes.
        #expect(try secondaries("barbell-squat").contains(.glutes))
    }

    @Test("A muscle is never both the prime mover and a secondary")
    func primaryAndSecondaryStayDisjoint() throws {
        for exercise in try ExerciseCatalog.bundled().all {
            #expect(Set(exercise.primaryMuscles).isDisjoint(with: Set(exercise.secondaryMuscles)),
                    "\(exercise.id) lists a muscle as both primary and secondary")
        }
    }
}
