import Testing
@testable import LiftingPlan

@Suite("Template plan builder")
struct TemplatePlanBuilderTests {

    @Test("Chooses a split appropriate to the number of days")
    func splitByDayCount() {
        #expect(TemplatePlanBuilder.splitTemplate(forDayCount: 1) == ["Full Body"])
        #expect(TemplatePlanBuilder.splitTemplate(forDayCount: 2) == ["Upper Body", "Lower Body"])
        #expect(TemplatePlanBuilder.splitTemplate(forDayCount: 3) == ["Push", "Pull", "Legs"])
        #expect(TemplatePlanBuilder.splitTemplate(forDayCount: 4).count == 4)
    }

    @Test("Builds one day per requested weekday, in order")
    func oneDayPerWeekday() {
        let plan = TemplatePlanBuilder.build(
            weekdays: [.friday, .monday, .wednesday],
            durationMinutes: 45,
            equipment: .fullGym,
            experience: .intermediate
        )
        #expect(plan.days.count == 3)
        // Sorted chronologically: Mon, Wed, Fri.
        #expect(plan.days.map(\.weekday) == [.monday, .wednesday, .friday])
    }

    @Test("Session size scales with duration")
    func sizeScalesWithDuration() {
        let short = TemplatePlanBuilder.build(weekdays: [.monday], durationMinutes: 30, equipment: .fullGym, experience: .intermediate)
        let long = TemplatePlanBuilder.build(weekdays: [.monday], durationMinutes: 75, equipment: .fullGym, experience: .intermediate)
        #expect(short.days[0].exercises.count == 4)
        #expect(long.days[0].exercises.count == 6)
    }

    @Test("First movements are compounds with longer rest")
    func compoundsFirst() {
        let plan = TemplatePlanBuilder.build(weekdays: [.monday], durationMinutes: 60, equipment: .fullGym, experience: .intermediate)
        let exercises = plan.days[0].exercises
        // Compounds (index 0,1) get the longer rest.
        #expect(exercises[0].restSeconds >= exercises[2].restSeconds)
        #expect(exercises[0].sets >= exercises[2].sets)
    }

    @Test("Bodyweight plans prescribe no external load")
    func bodyweightHasNoWeight() {
        let plan = TemplatePlanBuilder.build(weekdays: [.monday], durationMinutes: 45, equipment: .bodyweight, experience: .beginner)
        for exercise in plan.days[0].exercises {
            #expect(exercise.suggestedWeight == nil)
        }
        #expect(!plan.days[0].exercises.isEmpty)
    }

    @Test("Empty weekday list yields an empty plan")
    func emptyWeekdays() {
        let plan = TemplatePlanBuilder.build(weekdays: [], durationMinutes: 45, equipment: .fullGym, experience: .intermediate)
        #expect(plan.days.isEmpty)
    }
}
