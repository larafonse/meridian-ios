import Testing
import Foundation
import SwiftData
@testable import Meridian

@Suite("TemplateDetailSheet")
struct TemplateDetailTests {

    private func makeScore(volume: Double) -> TemplateWorkoutScore {
        TemplateWorkoutScore(
            templateID: UUID(),
            templateName: "Test",
            sessionID: UUID(),
            date: .now,
            totalVolume: volume
        )
    }

    @Test("volumeStats: empty array returns zero total and nil best/avg")
    func emptyScores() {
        let stats = volumeStats(from: [])
        #expect(stats.total == 0)
        #expect(stats.best == nil)
        #expect(stats.avg == nil)
    }

    @Test("volumeStats: single score returns correct total, best, avg")
    func singleScore() {
        let stats = volumeStats(from: [makeScore(volume: 1500)])
        #expect(stats.total == 1)
        #expect(stats.best == 1500)
        #expect(stats.avg == 1500)
    }

    @Test("volumeStats: multiple scores computes correct total, best, avg")
    func multipleScores() {
        let scores = [makeScore(volume: 1000), makeScore(volume: 2000), makeScore(volume: 3000)]
        let stats = volumeStats(from: scores)
        #expect(stats.total == 3)
        #expect(stats.best == 3000)
        #expect(stats.avg == 2000)
    }

    @Test("volumeStats: avg rounds correctly for uneven values")
    func unevenAvg() {
        let scores = [makeScore(volume: 1000), makeScore(volume: 2000)]
        let stats = volumeStats(from: scores)
        #expect(stats.avg == 1500)
    }
}
