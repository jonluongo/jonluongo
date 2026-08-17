import Foundation
import Testing
@testable import LiftingKit

/// The prescription a plan can now make: sets that differ from one another, and
/// how hard each of them is meant to be.
///
/// Every assertion here is about a fact surviving unchanged. Nothing in this
/// suite checks that a value is sensible — an RPE of 47 and a scale nobody has
/// heard of both round-trip, because judging them is not the app's job.
@Suite("Per-set prescription and intensity")
struct SetPrescriptionTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)

    private func document(_ exercises: [PlanDocumentExercise]) -> PlanDocument {
        PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            days: [PlanDocumentDay(weekday: .monday, focus: "Push", exercises: exercises)]
        )
    }

    private func roundTrip(_ document: PlanDocument) throws -> PlanDocument {
        let data = try PlanDocument.makeEncoder().encode(document)
        return try PlanDocument.makeDecoder().decode(PlanDocument.self, from: data)
    }

    private func firstExercise(in document: PlanDocument) throws -> PlanDocumentExercise {
        let day = try #require(document.weeks.first?.days.first)
        return try #require(day.exercises.first)
    }

    private func decoded(_ json: String) throws -> PlanDocument {
        try PlanDocument.makeDecoder().decode(PlanDocument.self, from: Data(json.utf8))
    }

    private func kg(_ value: Double) -> Mass { Mass(value: value, unit: .kilograms) }

    // MARK: - Sets that differ

    @Test("A drop set round-trips: three sets at one load and a fourth at a lower one")
    func dropSetSurvives() throws {
        let original = document([
            PlanDocumentExercise(
                exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
                displayName: "Barbell Bench Press",
                sets: [
                    SetPrescription(repRange: "8", suggestedLoad: kg(100)),
                    SetPrescription(repRange: "8", suggestedLoad: kg(100)),
                    SetPrescription(repRange: "8", suggestedLoad: kg(100)),
                    SetPrescription(
                        repRange: "AMRAP", suggestedLoad: kg(70), notes: "Drop set, to failure"),
                ]
            )
        ])
        let exercise = try firstExercise(in: try roundTrip(original))

        #expect(exercise.sets == 4, "the set count is how many sets were listed")
        #expect(exercise.prescribedSets.map(\.suggestedLoad) == [
            kg(100), kg(100), kg(100), kg(70),
        ])
        #expect(exercise.prescribedSets.map(\.repRange) == ["8", "8", "8", "AMRAP"])
        #expect(exercise.prescribedSets.last?.notes == "Drop set, to failure")
        #expect(try roundTrip(original) == original)
    }

    @Test("Ramping load across sets survives the round trip in the order written")
    func rampingLoadSurvives() throws {
        let original = document([
            PlanDocumentExercise(
                exerciseID: ExerciseID(rawValue: "barbell-back-squat"),
                displayName: "Barbell Back Squat",
                sets: [
                    SetPrescription(suggestedLoad: kg(60)),
                    SetPrescription(suggestedLoad: kg(70)),
                    SetPrescription(suggestedLoad: kg(80)),
                ],
                repRange: "5"
            )
        ])
        let exercise = try firstExercise(in: try roundTrip(original))

        #expect(exercise.prescribedSets.map { $0.suggestedLoad?.value } == [60, 70, 80])
        // The reps were stated once for the exercise, so every set carries them
        // — the plan said it, so reading it onto the sets is not inventing one.
        #expect(exercise.prescribedSets.map(\.repRange) == ["5", "5", "5"])
    }

    @Test("A back-off set keeps the load it was written with, unit and all")
    func backOffSetKeepsItsUnit() throws {
        let original = document([
            PlanDocumentExercise(
                exerciseID: ExerciseID(rawValue: "barbell-deadlift"),
                displayName: "Deadlift",
                sets: [
                    SetPrescription(repRange: "1", suggestedLoad: Mass(value: 405, unit: .pounds)),
                    SetPrescription(repRange: "5", suggestedLoad: Mass(value: 315, unit: .pounds)),
                ]
            )
        ])
        let loads = try firstExercise(in: try roundTrip(original)).prescribedSets
            .compactMap(\.suggestedLoad)

        #expect(loads == [Mass(value: 405, unit: .pounds), Mass(value: 315, unit: .pounds)])
        #expect(loads.first != Mass(value: 405, unit: .pounds).converted(to: .kilograms))
    }

    // MARK: - The uniform case stays the short one

    @Test("A uniform prescription writes a set count, not a list of identical sets")
    func uniformPrescriptionStaysTerse() throws {
        let original = document([
            PlanDocumentExercise(
                exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
                displayName: "Bench", sets: 3, repRange: "8"
            )
        ])
        let text = String(decoding: try PlanDocument.makeEncoder().encode(original), as: UTF8.self)

        #expect(text.contains("\"sets\" : 3"), "three sets of eight is not three objects")
        #expect(try roundTrip(original) == original)
    }

    @Test("A uniform prescription still reads as every set it prescribes")
    func uniformExpandsToEverySet() throws {
        let load = kg(60)
        let target = IntensityTarget(scale: .rpe, value: "8")
        let exercise = PlanDocumentExercise(
            exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
            displayName: "Bench", sets: 3, repRange: "8-12", suggestedLoad: load,
            intensity: target
        )

        #expect(exercise.prescribedSets.count == 3)
        #expect(exercise.prescribedSets.allSatisfy { $0.repRange == "8-12" })
        #expect(exercise.prescribedSets.allSatisfy { $0.suggestedLoad == load })
        #expect(exercise.prescribedSets.allSatisfy { $0.intensity == target })
    }

    @Test("An exercise that prescribes no sets prescribes none, rather than crashing")
    func noSetsIsNoSets() {
        let none = PlanDocumentExercise(
            exerciseID: ExerciseID(rawValue: "plank"), displayName: "Plank", sets: 0)
        #expect(none.prescribedSets.isEmpty)

        // A negative count is recorded as written — the audit found the format
        // accepts it — and prescribes no sets rather than trapping.
        let negative = PlanDocumentExercise(
            exerciseID: ExerciseID(rawValue: "plank"), displayName: "Plank", sets: -1)
        #expect(negative.sets == -1)
        #expect(negative.prescribedSets.isEmpty)
    }

    @Test("A listed set that states nothing of its own carries the exercise's prescription")
    func listedSetInheritsWhatItDoesNotState() throws {
        let exercise = PlanDocumentExercise(
            exerciseID: ExerciseID(rawValue: "barbell-bench-press"), displayName: "Bench",
            sets: [
                SetPrescription(),
                SetPrescription(repRange: "AMRAP", suggestedLoad: kg(70)),
            ],
            repRange: "8", suggestedLoad: kg(100),
            intensity: IntensityTarget(scale: .rpe, value: "8")
        )

        #expect(exercise.prescribedSets.first?.repRange == "8")
        #expect(exercise.prescribedSets.first?.suggestedLoad == kg(100))
        #expect(exercise.prescribedSets.first?.intensity == IntensityTarget(scale: .rpe, value: "8"))
        #expect(exercise.prescribedSets.last?.repRange == "AMRAP")
        #expect(exercise.prescribedSets.last?.suggestedLoad == kg(70))
    }

    @Test("An exercise that states no rep range gives its sets none rather than an empty string")
    func unstatedRepRangeStaysUnstated() {
        let exercise = PlanDocumentExercise(
            exerciseID: ExerciseID(rawValue: "plank"), displayName: "Plank", sets: 2)
        #expect(exercise.prescribedSets.allSatisfy { $0.repRange == nil })
    }

    // MARK: - Intensity, on whatever scale it was stated

    @Test("An RPE target round-trips without conversion")
    func rpeTargetRoundTrips() throws {
        let decoded = try roundTrip(document([
            PlanDocumentExercise(
                exerciseID: ExerciseID(rawValue: "barbell-back-squat"), displayName: "Squat",
                sets: 3, intensity: IntensityTarget(scale: .rpe, value: "8")
            )
        ]))
        let intensity = try #require(try firstExercise(in: decoded).intensity)

        #expect(intensity.scale == .rpe)
        #expect(intensity.scale.rawValue == "rpe")
        #expect(intensity.value == "8")
    }

    @Test("An RIR target round-trips without becoming an RPE")
    func rirTargetRoundTrips() throws {
        let decoded = try roundTrip(document([
            PlanDocumentExercise(
                exerciseID: ExerciseID(rawValue: "barbell-back-squat"), displayName: "Squat",
                sets: 3, intensity: IntensityTarget(scale: .repsInReserve, value: "2")
            )
        ]))
        let intensity = try #require(try firstExercise(in: decoded).intensity)

        #expect(intensity.scale == .repsInReserve)
        #expect(intensity.scale.rawValue == "rir")
        #expect(intensity.value == "2", "2 RIR is not 8 RPE unless a coach says so")
    }

    @Test("A percentage of one-rep max round-trips as the percentage it was written as")
    func percentTargetRoundTrips() throws {
        let decoded = try roundTrip(document([
            PlanDocumentExercise(
                exerciseID: ExerciseID(rawValue: "barbell-back-squat"), displayName: "Squat",
                sets: 3, intensity: IntensityTarget(scale: .percentOfOneRepMax, value: "80")
            )
        ]))
        let intensity = try #require(try firstExercise(in: decoded).intensity)

        #expect(intensity.scale == .percentOfOneRepMax)
        #expect(intensity.value == "80")
    }

    @Test("An intensity stated as a range is carried as written rather than resolved to an end")
    func intensityRangeIsCarriedWhole() throws {
        let decoded = try roundTrip(document([
            PlanDocumentExercise(
                exerciseID: ExerciseID(rawValue: "barbell-back-squat"), displayName: "Squat",
                sets: 3, intensity: IntensityTarget(scale: .rpe, value: "8-9")
            )
        ]))
        #expect(try firstExercise(in: decoded).intensity?.value == "8-9")
    }

    @Test("An exercise with no intensity target has none — not a zero and not a default")
    func absentIntensityStaysAbsent() throws {
        let decoded = try roundTrip(document([
            PlanDocumentExercise(
                exerciseID: ExerciseID(rawValue: "barbell-back-squat"),
                displayName: "Squat", sets: 3, repRange: "5", suggestedLoad: kg(140)
            )
        ]))
        let exercise = try firstExercise(in: decoded)

        #expect(exercise.intensity == nil)
        #expect(exercise.prescribedSets.allSatisfy { $0.intensity == nil },
                "a load is not an intensity target, and nothing may infer one from it")
    }

    @Test("A scale this build has never heard of round-trips intact rather than being dropped")
    func unknownScaleRoundTrips() throws {
        let velocity = IntensityScale(rawValue: "metres-per-second")
        let decoded = try roundTrip(document([
            PlanDocumentExercise(
                exerciseID: ExerciseID(rawValue: "barbell-back-squat"), displayName: "Squat",
                sets: 3, intensity: IntensityTarget(scale: velocity, value: "0.45")
            )
        ]))
        let intensity = try #require(try firstExercise(in: decoded).intensity)

        #expect(intensity.scale == velocity)
        #expect(intensity.scale.isKnown == false)
        #expect(intensity.value == "0.45")
    }

    @Test("Per-set intensity overrides the exercise's for that set alone")
    func perSetIntensityApplies() throws {
        let decoded = try roundTrip(document([
            PlanDocumentExercise(
                exerciseID: ExerciseID(rawValue: "barbell-back-squat"), displayName: "Squat",
                sets: [
                    SetPrescription(),
                    SetPrescription(intensity: IntensityTarget(scale: .rpe, value: "9.5")),
                ],
                repRange: "3", intensity: IntensityTarget(scale: .rpe, value: "7")
            )
        ]))
        let sets = try firstExercise(in: decoded).prescribedSets

        #expect(sets.map { $0.intensity?.value } == ["7", "9.5"])
    }

    // MARK: - Reading what was written in JSON

    @Test("A per-set list written as JSON decodes as the sets it lists")
    func perSetJSONDecodes() throws {
        let json = """
        {
          "version": 3, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "weeks": [{"days": [{
            "weekday": 2,
            "exercises": [{
              "exerciseID": "barbell-back-squat", "displayName": "Squat",
              "repRange": "5",
              "sets": [
                {"suggestedLoad": {"value": 60, "unit": "kg"}},
                {"suggestedLoad": {"value": 70, "unit": "kg"}},
                {"suggestedLoad": {"value": 80, "unit": "kg"},
                 "intensity": {"scale": "rpe", "value": "8"},
                 "notes": "Top set"}
              ]
            }]
          }]}]
        }
        """
        let exercise = try firstExercise(in: try decoded(json))

        #expect(exercise.sets == 3)
        #expect(exercise.prescribedSets.map { $0.suggestedLoad?.value } == [60, 70, 80])
        #expect(exercise.prescribedSets.map(\.repRange) == ["5", "5", "5"])
        #expect(exercise.prescribedSets.last?.intensity == IntensityTarget(scale: .rpe, value: "8"))
        #expect(exercise.prescribedSets.last?.notes == "Top set")
    }

    @Test("An unknown key inside a listed set is refused, naming the key and where it sat")
    func unknownKeyInsideASetIsRefused() throws {
        let json = """
        {
          "version": 3, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "weeks": [{"days": [{
            "weekday": 2,
            "exercises": [{
              "exerciseID": "barbell-back-squat", "displayName": "Squat",
              "sets": [{"clusterRest": 20}]
            }]
          }]}]
        }
        """
        let error = #expect(throws: DocumentRefusal.self) { try decoded(json) }
        let message = try #require(error?.errorDescription)

        #expect(message.contains("clusterRest"))
        #expect(message.contains("weeks → 0 → days → 0 → exercises → 0 → sets → 0"))
    }

    @Test("An unknown key inside an intensity target is refused too")
    func unknownKeyInsideIntensityIsRefused() throws {
        let json = """
        {
          "version": 3, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "weeks": [{"days": [{
            "weekday": 2,
            "exercises": [{
              "exerciseID": "barbell-back-squat", "displayName": "Squat", "sets": 3,
              "intensity": {"scale": "rpe", "value": "8", "ceiling": 10}
            }]
          }]}]
        }
        """
        #expect(try #require(#expect(throws: DocumentRefusal.self) { try decoded(json) }?
            .errorDescription).contains("ceiling"))
    }

    @Test("An intensity that does not say what scale it is on is refused, not guessed")
    func intensityWithoutAScaleIsRefused() throws {
        let json = """
        {
          "version": 3, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "weeks": [{"days": [{
            "weekday": 2,
            "exercises": [{
              "exerciseID": "barbell-back-squat", "displayName": "Squat", "sets": 3,
              "intensity": {"value": "8"}
            }]
          }]}]
        }
        """
        #expect(throws: (any Error).self) { try decoded(json) }
    }

    // MARK: - The format this one grew out of

    @Test("A version 2 document still imports, sets and all")
    func versionTwoStillDecodes() throws {
        let json = """
        {
          "version": 2, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "title": "Block",
          "weeks": [
            {"label": "Accumulation", "days": [{
              "weekday": 2, "focus": "Lower",
              "exercises": [{
                "exerciseID": "barbell-back-squat", "displayName": "Squat",
                "sets": 5, "repRange": "5", "restSeconds": 180,
                "suggestedLoad": {"value": 275, "unit": "lb"},
                "tempo": "3-0-1-0", "notes": "Belt from the third set."
              }]
            }]},
            {"label": "Deload", "isDeload": true, "days": []}
          ]
        }
        """
        let document = try decoded(json)
        let exercise = try firstExercise(in: document)

        #expect(document.version == 2)
        #expect(document.weekCount == 2)
        #expect(document.weeks.last?.isDeload == true)
        #expect(exercise.sets == 5)
        #expect(exercise.repRange == "5")
        #expect(exercise.suggestedLoad == Mass(value: 275, unit: .pounds))
        #expect(exercise.intensity == nil, "a format that could not say it did not say it")
        #expect(exercise.prescribedSets.count == 5)
    }

    @Test("A document from a format later than this one is still refused before its keys are")
    func laterVersionStillRefusedFirst() throws {
        let json = """
        {
          "version": 5, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "weeks": [], "clusterSets": true
        }
        """
        let error = #expect(throws: DocumentRefusal.self) { try decoded(json) }
        #expect(error == .laterVersion(5, understood: PlanDocument.currentVersion))
    }

    @Test("The per-set shape arrived in version 3, and every version since still reads it")
    func perSetShapeIsReadableFromVersionThreeOn() {
        #expect(PlanDocument.currentVersion >= 3)
    }
}
