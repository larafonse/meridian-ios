import Testing
@testable import Meridian

@Suite("ActivitySummary")
struct ActivitySummaryTests {

    @Test("move progress is ratio of energy burned to goal")
    func moveProgressRatio() {
        let summary = ActivitySummary(moveEnergy: 300, moveGoal: 600, exerciseMinutes: 0, exerciseGoal: 30, standHours: 0, standGoal: 12)
        #expect(summary.moveProgress == 0.5)
    }

    @Test("exercise progress is ratio of minutes to goal")
    func exerciseProgressRatio() {
        let summary = ActivitySummary(moveEnergy: 0, moveGoal: 600, exerciseMinutes: 20, exerciseGoal: 30, standHours: 0, standGoal: 12)
        #expect(abs(summary.exerciseProgress - 20.0 / 30.0) < 0.001)
    }

    @Test("stand progress is ratio of hours to goal")
    func standProgressRatio() {
        let summary = ActivitySummary(moveEnergy: 0, moveGoal: 600, exerciseMinutes: 0, exerciseGoal: 30, standHours: 9, standGoal: 12)
        #expect(summary.standProgress == 0.75)
    }

    @Test("progress can exceed 1.0 when goal is surpassed")
    func progressExceedsOne() {
        let summary = ActivitySummary(moveEnergy: 700, moveGoal: 600, exerciseMinutes: 0, exerciseGoal: 30, standHours: 0, standGoal: 12)
        #expect(summary.moveProgress > 1.0)
    }

    @Test("progress is zero when goal is zero")
    func progressZeroGoal() {
        let summary = ActivitySummary(moveEnergy: 100, moveGoal: 0, exerciseMinutes: 0, exerciseGoal: 0, standHours: 0, standGoal: 0)
        #expect(summary.moveProgress == 0)
        #expect(summary.exerciseProgress == 0)
        #expect(summary.standProgress == 0)
    }
}
