import Testing
@testable import LiftingPlan

@MainActor
@Suite("Rest timer math")
struct RestTimerTests {

    @Test("Starting seeds remaining, total, and running state")
    func start() {
        let timer = RestTimerModel()
        timer.start(seconds: 90, context: "Bench — set 2")
        #expect(timer.total == 90)
        #expect(timer.remaining == 90)
        #expect(timer.isRunning)
        #expect(timer.formattedRemaining == "1:30")
        #expect(timer.progress == 0)
        timer.stop()
    }

    @Test("Adding time extends the total")
    func addTime() {
        let timer = RestTimerModel()
        timer.start(seconds: 60, context: "Squat")
        timer.addTime(30)
        #expect(timer.total == 90)
        timer.stop()
    }

    @Test("Stopping resets to idle")
    func stop() {
        let timer = RestTimerModel()
        timer.start(seconds: 60, context: "Row")
        timer.stop()
        #expect(!timer.isRunning)
        #expect(timer.remaining == 0)
    }

    @Test("Formatting pads seconds")
    func formatting() {
        let timer = RestTimerModel()
        timer.start(seconds: 65, context: "")
        #expect(timer.formattedRemaining == "1:05")
        timer.stop()
    }
}
