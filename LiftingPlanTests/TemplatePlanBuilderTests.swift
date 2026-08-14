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

    @Test("Building returns an empty plan until catalog selection lands")
    func buildIsEmptyForNow() {
        let plan = TemplatePlanBuilder.build(
            weekdays: [.monday, .wednesday], durationMinutes: 45,
            equipment: .fullGym, experience: .intermediate
        )
        #expect(plan.days.isEmpty)
    }

    @Test("Empty weekday list yields an empty plan")
    func emptyWeekdays() {
        let plan = TemplatePlanBuilder.build(weekdays: [], durationMinutes: 45, equipment: .fullGym, experience: .intermediate)
        #expect(plan.days.isEmpty)
    }
}
