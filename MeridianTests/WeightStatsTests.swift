import Testing
import Foundation
@testable import Meridian

@Suite("WeightStats")
struct WeightStatsTests {

    private func makeEntry(weight: Double, unit: String = "lbs", daysAgo: Int = 0) -> WeightEntry {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return WeightEntry(weight: weight, unit: unit, recordedAt: date)
    }

    @Test("empty entries returns nil stats")
    func emptyEntries() {
        let stats = computeStats(entries: [])
        #expect(stats.current == nil)
        #expect(stats.change7d == nil)
        #expect(stats.trend == .unknown)
        #expect(stats.min == nil)
        #expect(stats.max == nil)
    }

    @Test("single entry returns correct current weight")
    func singleEntry() {
        let stats = computeStats(entries: [makeEntry(weight: 180.0)])
        #expect(stats.current == 180.0)
        #expect(stats.min == 180.0)
        #expect(stats.max == 180.0)
    }

    @Test("7-day change computes correctly")
    func sevenDayChange() {
        let entries = [
            makeEntry(weight: 178.0, daysAgo: 0),
            makeEntry(weight: 180.0, daysAgo: 8),
        ]
        let stats = computeStats(entries: entries)
        #expect(stats.change7d == -2.0)
    }

    @Test("trend returns up when weight increasing")
    func trendUp() {
        let entries = [
            makeEntry(weight: 185.0, daysAgo: 0),
            makeEntry(weight: 183.0, daysAgo: 2),
            makeEntry(weight: 180.0, daysAgo: 4),
        ]
        let stats = computeStats(entries: entries)
        #expect(stats.trend == .up)
    }

    @Test("trend returns down when weight decreasing")
    func trendDown() {
        let entries = [
            makeEntry(weight: 175.0, daysAgo: 0),
            makeEntry(weight: 178.0, daysAgo: 2),
            makeEntry(weight: 182.0, daysAgo: 4),
        ]
        let stats = computeStats(entries: entries)
        #expect(stats.trend == .down)
    }

    @Test("min and max are correct across entries")
    func minMax() {
        let entries = [
            makeEntry(weight: 178.0, daysAgo: 0),
            makeEntry(weight: 195.0, daysAgo: 10),
            makeEntry(weight: 165.0, daysAgo: 20),
        ]
        let stats = computeStats(entries: entries)
        #expect(stats.min == 165.0)
        #expect(stats.max == 195.0)
    }
}
