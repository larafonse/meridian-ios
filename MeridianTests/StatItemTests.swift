import Testing
import Foundation
@testable import Meridian

@Suite("StatItem builders")
struct StatItemTests {

    private func makeEntry(weight: Double, unit: String = "lbs", daysAgo: Int = 0) -> WeightEntry {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return WeightEntry(weight: weight, unit: unit, recordedAt: date)
    }

    // MARK: forWeight

    @Test("forWeight with no entries returns WGHT ticker and -- value")
    func weightNoEntries() {
        let item = StatItem.forWeight(entries: [])
        #expect(item.ticker == "WGHT")
        #expect(item.name == "Body Weight")
        #expect(item.latestValue == "--")
        #expect(item.sparklineData == [0, 0])
    }

    @Test("forWeight with single entry pads sparkline")
    func weightSingleEntry() {
        let item = StatItem.forWeight(entries: [makeEntry(weight: 175.0)])
        #expect(item.sparklineData == [0, 175.0])
        #expect(item.latestValue == "175.0 lbs")
    }

    @Test("forWeight uses last 10 entries for sparkline")
    func weightSparklineCappedAt10() {
        let entries = (1...15).map { makeEntry(weight: Double($0), daysAgo: 15 - $0) }
        let item = StatItem.forWeight(entries: entries)
        #expect(item.sparklineData.count == 10)
        #expect(item.sparklineData.last == 15.0)
    }

    @Test("forWeight id is stable across calls")
    func weightStableID() {
        let item1 = StatItem.forWeight(entries: [])
        let item2 = StatItem.forWeight(entries: [])
        #expect(item1.id == item2.id)
    }

    // MARK: forTemplate

    @Test("forTemplate with no scores returns -- value")
    func templateNoScores() {
        let template = WorkoutTemplate(name: "Squat Program", workoutType: "strength", workoutTypeDisplayName: "Strength")
        let item = StatItem.forTemplate(template, scores: [])
        #expect(item.latestValue == "--")
        #expect(item.sparklineData == [0, 0])
        #expect(item.ticker == "SP")
        #expect(item.name == "Squat Program")
    }

    @Test("forTemplate id matches template id")
    func templateIDMatchesTemplate() {
        let template = WorkoutTemplate(name: "Push Pull", workoutType: "strength", workoutTypeDisplayName: "Strength")
        let item = StatItem.forTemplate(template, scores: [])
        #expect(item.id == template.id)
    }

    // MARK: forMetric

    private func makeMetric(name: String, valueType: ValueType = .decimal, unit: String = "mmHg") -> Metric {
        Metric(name: name, valueType: valueType, unit: unit, sortOrder: 0)
    }

    private func makeMetricEntry(metric: Metric, value: Double, daysAgo: Int = 0) -> MetricEntry {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return MetricEntry(metric: metric, value: value, recordedAt: date)
    }

    @Test("forMetric ticker uses tickerSymbol for multi-word name")
    func metricTickerMultiWord() {
        let m = makeMetric(name: "Blood Pressure")
        #expect(StatItem.forMetric(m, entries: []).ticker == "BP")
    }

    @Test("forMetric ticker for short single-word name is not padded")
    func metricTickerShortName() {
        let m = makeMetric(name: "HR")
        #expect(StatItem.forMetric(m, entries: []).ticker == "HR")
    }

    @Test("forMetric latestValue is double dash when no entries")
    func metricLatestValueEmpty() {
        let m = makeMetric(name: "Weight", unit: "lbs")
        #expect(StatItem.forMetric(m, entries: []).latestValue == "--")
    }

    @Test("forMetric latestValue formatted for decimal metric with 1 decimal place")
    func metricLatestValueDecimal() {
        let m = makeMetric(name: "Weight", valueType: .decimal, unit: "lbs")
        let entry = makeMetricEntry(metric: m, value: 182.5)
        #expect(StatItem.forMetric(m, entries: [entry]).latestValue == "182.5 lbs")
    }

    @Test("forMetric latestValue formatted for integer metric with no decimal")
    func metricLatestValueInteger() {
        let m = makeMetric(name: "Systolic", valueType: .integer, unit: "mmHg")
        let entry = makeMetricEntry(metric: m, value: 120.0)
        #expect(StatItem.forMetric(m, entries: [entry]).latestValue == "120 mmHg")
    }

    @Test("forMetric id matches metric id")
    func metricIDMatchesMetric() {
        let m = makeMetric(name: "Systolic")
        #expect(StatItem.forMetric(m, entries: []).id == m.id)
    }

    @Test("forTemplate filters scores by templateID")
    func templateFiltersScores() {
        let t1 = WorkoutTemplate(name: "Alpha", workoutType: "strength", workoutTypeDisplayName: "Strength")
        let t2 = WorkoutTemplate(name: "Beta", workoutType: "strength", workoutTypeDisplayName: "Strength")
        let scores = [
            TemplateWorkoutScore(templateID: t1.id, templateName: "Alpha",
                                 sessionID: UUID(), date: .now, totalVolume: 1000),
            TemplateWorkoutScore(templateID: t2.id, templateName: "Beta",
                                 sessionID: UUID(), date: .now, totalVolume: 5000),
        ]
        let item = StatItem.forTemplate(t1, scores: scores)
        #expect(item.sparklineData.last == 1000.0)
        #expect(item.latestValue == "1,000 lbs")
    }
}
