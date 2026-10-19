import Foundation

struct MetricStats {
    let current: Double?
    let change7d: Double?
    let trend: WeightStats.Trend
    let min: Double?
    let max: Double?
    let unit: String
    let valueType: ValueType
}

func computeMetricStats(entries: [MetricEntry], metric: Metric) -> MetricStats {
    guard !entries.isEmpty else {
        return MetricStats(
            current: nil, change7d: nil, trend: .unknown,
            min: nil, max: nil,
            unit: metric.unit, valueType: metric.valueType
        )
    }

    let sorted = entries.sorted { $0.recordedAt > $1.recordedAt }
    let current = sorted.first?.value

    // 7-day change
    let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    let older = sorted.first { $0.recordedAt <= sevenDaysAgo }
    let change7d: Double? = {
        guard let c = current, let o = older?.value else { return nil }
        return (c - o).rounded(to: 1)
    }()

    // Trend: slope across last 3 entries
    let trend: WeightStats.Trend = {
        guard sorted.count >= 3 else { return .unknown }
        let a = sorted[2].value
        let c = sorted[0].value
        let slope = (c - a) / 2
        if slope > 0.1 { return .up }
        if slope < -0.1 { return .down }
        return .flat
    }()

    let values = sorted.map { $0.value }
    return MetricStats(
        current: current,
        change7d: change7d,
        trend: trend,
        min: values.min(),
        max: values.max(),
        unit: metric.unit,
        valueType: metric.valueType
    )
}

private extension Double {
    func rounded(to places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
