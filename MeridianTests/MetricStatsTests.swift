import Testing
import Foundation
@testable import Meridian

@Suite("MetricStats")
struct MetricStatsTests {
    private func makeMetric(valueType: ValueType = .decimal, unit: String = "mmHg") -> Metric {
        Metric(name: "Test", valueType: valueType, unit: unit, sortOrder: 0)
    }

    private func makeEntry(metric: Metric, value: Double, daysAgo: Int = 0) -> MetricEntry {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return MetricEntry(metric: metric, value: value, recordedAt: date)
    }

    @Test("empty entries returns nil stats")
    func emptyEntries() {
        let m = makeMetric()
        let stats = computeMetricStats(entries: [], metric: m)
        #expect(stats.current == nil)
        #expect(stats.change7d == nil)
        #expect(stats.trend == .unknown)
        #expect(stats.min == nil)
        #expect(stats.max == nil)
    }

    @Test("single entry returns correct current")
    func singleEntry() {
        let m = makeMetric()
        let stats = computeMetricStats(entries: [makeEntry(metric: m, value: 120.0)], metric: m)
        #expect(stats.current == 120.0)
        #expect(stats.min == 120.0)
        #expect(stats.max == 120.0)
    }

    @Test("7-day change nil when no entry older than 7 days")
    func sevenDayChangeNilWhenNoOlderEntry() {
        let m = makeMetric()
        let stats = computeMetricStats(entries: [makeEntry(metric: m, value: 120.0, daysAgo: 3)], metric: m)
        #expect(stats.change7d == nil)
    }

    @Test("7-day change computes correctly")
    func sevenDayChange() {
        let m = makeMetric()
        let entries = [makeEntry(metric: m, value: 118.0, daysAgo: 0),
                       makeEntry(metric: m, value: 120.0, daysAgo: 8)]
        let stats = computeMetricStats(entries: entries, metric: m)
        #expect(stats.change7d == -2.0)
    }

    @Test("trend up when values increasing")
    func trendUp() {
        let m = makeMetric()
        let entries = [makeEntry(metric: m, value: 125.0, daysAgo: 0),
                       makeEntry(metric: m, value: 122.0, daysAgo: 2),
                       makeEntry(metric: m, value: 118.0, daysAgo: 4)]
        #expect(computeMetricStats(entries: entries, metric: m).trend == .up)
    }

    @Test("trend down when values decreasing")
    func trendDown() {
        let m = makeMetric()
        let entries = [makeEntry(metric: m, value: 115.0, daysAgo: 0),
                       makeEntry(metric: m, value: 119.0, daysAgo: 2),
                       makeEntry(metric: m, value: 124.0, daysAgo: 4)]
        #expect(computeMetricStats(entries: entries, metric: m).trend == .down)
    }

    @Test("valueType propagated from metric")
    func valueTypePropagated() {
        let m = makeMetric(valueType: .integer)
        let stats = computeMetricStats(entries: [], metric: m)
        #expect(stats.valueType == .integer)
    }

    @Test("unit propagated from metric")
    func unitPropagated() {
        let m = makeMetric(unit: "bpm")
        let stats = computeMetricStats(entries: [], metric: m)
        #expect(stats.unit == "bpm")
    }
}
