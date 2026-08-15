import Testing
import Foundation
@testable import LiftingKit

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

    /// Both bundled files now live in the package rather than the app bundle,
    /// so they resolve through `Bundle.module`. A resource that fails to
    /// resolve does not look like an error — it looks like an empty catalog —
    /// which is exactly why this asserts the URLs rather than trusting the
    /// build to have copied them.
    ///
    /// `assembly-rules.json` is deliberately decoded by nothing in Swift: every
    /// number in it is a training opinion, and the app makes no training
    /// decisions. It ships as material Claude reads. That is precisely why it
    /// needs a test — nothing else would notice if it stopped shipping.
    @Test("Both bundled reference files resolve from the package bundle")
    func bundledResourcesResolve() throws {
        let exercises = try #require(
            Bundle.module.url(forResource: "exercises", withExtension: "json"),
            "exercises.json did not resolve from Bundle.module"
        )
        let rules = try #require(
            Bundle.module.url(forResource: "assembly-rules", withExtension: "json"),
            "assembly-rules.json did not resolve from Bundle.module"
        )

        // Read and parse both, so a zero-byte or truncated copy fails here
        // rather than surfacing as absent data somewhere downstream.
        for url in [exercises, rules] {
            let data = try Data(contentsOf: url)
            #expect(!data.isEmpty, "\(url.lastPathComponent) is empty")
            let parsed = try JSONSerialization.jsonObject(with: data)
            let object = try #require(
                parsed as? [String: Any],
                "\(url.lastPathComponent) is not a JSON object"
            )
            #expect(
                object["version"] is Int,
                "\(url.lastPathComponent) carries no version stamp"
            )
        }
    }

    /// The version the shipped `exercises.json` must declare. Pinned rather
    /// than range-checked: `Tools/build-catalog.py` requires `CATALOG_VERSION`
    /// to be bumped whenever catalog data changes, and this is what makes
    /// forgetting that bump a build failure instead of a silent lie in every
    /// plan stamped afterwards. Bump it here in the same commit as there.
    private static let expectedCatalogVersion = 5

    @Test("The bundled catalog declares the current version")
    func catalogDeclaresVersion() throws {
        #expect(try ExerciseCatalog.bundled().version == Self.expectedCatalogVersion)
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

    @Test("Every exercise carries a difficulty this build recognizes")
    func difficultyPresentAndKnown() throws {
        for exercise in try ExerciseCatalog.bundled().all {
            #expect(exercise.difficulty.isKnown,
                    "\(exercise.id) has unrecognized difficulty \(exercise.difficulty)")
        }
    }

    @Test("Difficulty matches what a lifter would expect for known movements")
    func difficultyIsSensible() throws {
        let catalog = try ExerciseCatalog.bundled()
        func difficulty(_ id: String) throws -> Difficulty {
            try #require(catalog.exercise(id: ExerciseID(rawValue: id))).difficulty
        }
        // An Olympic lift is not a beginner movement.
        #expect(try difficulty("power-clean") == .advanced)
        // A machine isolation is.
        #expect(try difficulty("machine-hip-abduction") == .beginner)
    }

    @Test("Loading a barbell or trap bar for a compound lift is never beginner difficulty")
    func loadedCompoundBarbellLiftsAreNotBeginner() throws {
        let barbellLike: Set<EquipmentType> = [.barbell, .trapBar]
        let offenders = try ExerciseCatalog.bundled().all.filter {
            $0.mechanic == .compound
                && barbellLike.contains($0.equipment)
                && $0.difficulty == .beginner
        }
        #expect(offenders.isEmpty,
                "compound barbell/trap-bar lifts rated beginner: \(offenders.map(\.id.rawValue).sorted())")
    }

    // MARK: - Task 3: audit corrections

    /// Class-level guard against the bug class, not just the two exercises
    /// the audit happened to name. An exercise whose slug contains any of
    /// these tokens asks the body to support load across more than one
    /// joint for the duration of the movement — a loaded carry (`carry`,
    /// `farmer`), a suspended or supported hang (`hang`, `hold`), a
    /// multi-position transition (`get-up`), or a plank (`plank`, which
    /// moves no joint but loads shoulders, spine, and hips simultaneously
    /// to resist collapse) — so none of them should ever be `isolation`.
    ///
    /// The original wording from the audit named `carry`/`hold`/`get-up`/
    /// `farmer` only. It missed `dead-hang` (slug token is `hang`, not
    /// `hold`) and the three planks (`plank`) entirely, even though both
    /// groups have the identical multi-joint-under-static-load shape as the
    /// exercises it did name. This test widens the token list to `hang` and
    /// `plank` so the guard actually matches its own stated rationale rather
    /// than the four slugs someone happened to type.
    ///
    /// `plate-pinch` is the deliberate exception discussed elsewhere in this
    /// file: pinching plates loads the fingers and nothing else, which is
    /// isolation by the ordinary joint-count definition. Its slug contains
    /// none of these tokens, so it is not swept up here and needs no
    /// exclusion list.
    ///
    /// Matching is on hyphen-delimited tokens, not substrings, for the
    /// single-word tokens: a naive `slug.contains("hang")` also fires inside
    /// `hanging-knee-raises`, which really is isolation (a hip-flexion ab
    /// exercise that merely starts from a hang, not a load-bearing hold) —
    /// this is exactly the substring-vs-token bug Task 2 fixed for the
    /// derivation rules, and it would have made this guard flaky the same
    /// way. `get-up` is checked as a substring because it is inherently a
    /// two-token phrase; the catalog has no other slug containing it.
    @Test("No carry, hang, hold, get-up, or plank exercise is tagged isolation")
    func loadBearingHoldsAreNeverIsolation() throws {
        let singleWordTokens: Set<String> = ["carry", "hold", "farmer", "hang", "plank"]
        let offenders = try ExerciseCatalog.bundled().all.filter { exercise in
            let slug = exercise.id.rawValue
            let tokens = Set(slug.split(separator: "-").map(String.init))
            let matchesToken = !tokens.isDisjoint(with: singleWordTokens)
            let matchesGetUp = slug.contains("get-up")
            return (matchesToken || matchesGetUp) && exercise.mechanic == .isolation
        }
        #expect(offenders.isEmpty,
                "load-bearing holds tagged isolation: \(offenders.map(\.id.rawValue).sorted())")
    }

    @Test("Jefferson curls are a hinge on hamstrings and lower back, not a biceps curl")
    func jeffersonCurlsAreHinges() throws {
        let catalog = try ExerciseCatalog.bundled()
        let slugs = [
            "barbell-spinal-jefferson-curl", "bodyweight-spinal-jefferson-curl",
            "dumbbell-spinal-jefferson-curl", "kettlebell-spinal-jefferson-curl",
        ]
        for slug in slugs {
            let exercise = try #require(catalog.exercise(id: ExerciseID(rawValue: slug)),
                                        "\(slug) missing from catalog")
            #expect(exercise.pattern == .hinge, "\(slug) pattern is \(exercise.pattern)")
            #expect(exercise.mechanic == .compound, "\(slug) mechanic is \(exercise.mechanic)")
            #expect(exercise.difficulty != .beginner,
                    "\(slug) is loaded spinal flexion, not a beginner movement")
            #expect(exercise.primaryMuscles.contains(.lowerBack),
                    "\(slug) primary muscles are \(exercise.primaryMuscles)")
            #expect(!exercise.primaryMuscles.contains(.biceps),
                    "\(slug) still lists biceps as a prime mover")
        }
    }

    @Test("Carries, a farmer's carry, a Turkish get-up, and a dead hang are compound")
    func namedLoadBearingHoldsAreCompound() throws {
        let catalog = try ExerciseCatalog.bundled()
        let slugs = [
            "kettlebell-turkish-get-up", "kettlebell-farmers-carry", "dead-hang",
            "elbow-side-plank", "front-plank", "hand-plank", "bird-dog", "sled-push",
        ]
        for slug in slugs {
            let exercise = try #require(catalog.exercise(id: ExerciseID(rawValue: slug)),
                                        "\(slug) missing from catalog")
            #expect(exercise.mechanic == .compound, "\(slug) mechanic is \(exercise.mechanic)")
        }
    }

    @Test("A plate pinch is isolation: it loads the fingers and nothing else")
    func platePinchStaysIsolation() throws {
        let catalog = try ExerciseCatalog.bundled()
        let exercise = try #require(catalog.exercise(id: ExerciseID(rawValue: "plate-pinch")))
        #expect(exercise.mechanic == .isolation, "plate-pinch mechanic is \(exercise.mechanic)")
    }

    @Test("Upright rows are a vertical shoulder movement, not a horizontal pull")
    func uprightRowsAreNotHorizontalPulls() throws {
        let catalog = try ExerciseCatalog.bundled()
        for slug in ["barbell-upright-row", "dumbbell-upright-row"] {
            let exercise = try #require(catalog.exercise(id: ExerciseID(rawValue: slug)),
                                        "\(slug) missing from catalog")
            #expect(exercise.pattern == .raise, "\(slug) pattern is \(exercise.pattern)")
            #expect(exercise.mechanic == .compound, "\(slug) mechanic is \(exercise.mechanic)")
        }
    }

    @Test("Jumping jacks and jump rope are beginner plyometrics; box jumps and the rest stay advanced")
    func plyometricDifficultyIsNotOneSizeFitsAll() throws {
        let catalog = try ExerciseCatalog.bundled()
        func difficulty(_ id: String) throws -> Difficulty {
            try #require(catalog.exercise(id: ExerciseID(rawValue: id)),
                        "\(id) missing from catalog").difficulty
        }
        // Low-impact, rhythmic conditioning moves: genuinely beginner.
        #expect(try difficulty("jumping-jack") == .beginner)
        #expect(try difficulty("jump-rope") == .beginner)
        // Explosive jump-training with real landing/skill risk: still advanced.
        // These must NOT regress to intermediate as a side effect of fixing
        // the two beginner exceptions above.
        #expect(try difficulty("box-jump") == .advanced)
        #expect(try difficulty("burpee") == .advanced)
        #expect(try difficulty("jump-squats") == .advanced)
        #expect(try difficulty("man-maker") == .advanced)
        #expect(try difficulty("wall-ball") == .advanced)
    }

    // MARK: - Task 5: equipment-requiring cardio is not tagged bodyweight

    /// Cycling requires a bike, whether stationary or road. All five
    /// cycling entries — plus `steady-state-ride`, the same activity under a
    /// different name — must ship as `.cardioMachine`, never `.bodyweight`.
    /// This is the defect the audit found: the generator's `bodyweight`
    /// default silently applied to slugs no equipment keyword matched.
    @Test("No cycling entry is tagged bodyweight")
    func cyclingRequiresEquipment() throws {
        let catalog = try loaded()
        let slugs = [
            "cycling-cooldown", "cycling-intervals", "cycling-sprint",
            "cycling-warmup", "indoor-cycling-spin", "steady-state-ride",
        ]
        for slug in slugs {
            let exercise = try #require(catalog.exercise(id: ExerciseID(rawValue: slug)),
                                        "\(slug) missing from catalog")
            #expect(exercise.equipment == .cardioMachine,
                    "\(slug) equipment is \(exercise.equipment)")
        }
    }

    /// Swimming requires a pool. These entries must never ship as
    /// `.bodyweight`, which would let a bodyweight-only lifter be handed a
    /// swim workout. There is no equipment-access tier that grants `.pool`
    /// yet (see `EquipmentAccess`), so these are correctly modeled but
    /// currently unreachable by plan generation — that gap is covered by
    /// `EquipmentAccessTests.poolIsNotYetReachableByAnyTier`, not here.
    @Test("No swimming entry is tagged bodyweight")
    func swimmingRequiresEquipment() throws {
        let catalog = try loaded()
        let slugs = [
            "backstroke-swim", "breaststroke-swim", "butterfly-swim",
            "freestyle-swim", "swim-kick-drill", "swim-pull-drill",
            "swim-sprint-intervals",
        ]
        for slug in slugs {
            let exercise = try #require(catalog.exercise(id: ExerciseID(rawValue: slug)),
                                        "\(slug) missing from catalog")
            #expect(exercise.equipment == .pool, "\(slug) equipment is \(exercise.equipment)")
        }
    }

    /// A captain's chair is a fixed gym apparatus, not "no equipment".
    @Test("Captain's chair knee raise is not tagged bodyweight")
    func captainsChairRequiresEquipment() throws {
        let catalog = try loaded()
        let exercise = try #require(
            catalog.exercise(id: ExerciseID(rawValue: "captains-chair-knee-raise")))
        #expect(exercise.equipment != .bodyweight, "equipment is \(exercise.equipment)")
    }

    /// Running and hiking genuinely need no equipment. A fix for the cycling
    /// and swimming defects above must not sweep these up along with it —
    /// this test is the guard against that over-correction.
    @Test("Running and hiking entries stay tagged bodyweight")
    func runningAndHikingStayBodyweight() throws {
        let catalog = try loaded()
        let slugs = [
            "long-run", "tempo-run", "trail-run", "hiking",
            "hill-climb-repeats", "running-intervals", "running-cooldown",
            "mountain-climber", "shadow-boxing",
        ]
        for slug in slugs {
            let exercise = try #require(catalog.exercise(id: ExerciseID(rawValue: slug)),
                                        "\(slug) missing from catalog")
            #expect(exercise.equipment == .bodyweight,
                    "\(slug) equipment is \(exercise.equipment), expected bodyweight")
        }
    }
}
