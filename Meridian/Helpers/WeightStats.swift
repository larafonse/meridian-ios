import Foundation
import SwiftData

struct WeightStats {
    let current: Double?
    let change7d: Double?
    let trend: Trend
    let min: Double?
    let max: Double?
    let unit: String

    enum Trend: Equatable {
        case up, down, flat, unknown
    }
}

func computeStats(entries: [WeightEntry]) -> WeightStats {
    guard !entries.isEmpty else {
        return WeightStats(current: nil, change7d: nil, trend: .unknown, min: nil, max: nil, unit: "lbs")
    }

    let sorted = entries.sorted { $0.recordedAt > $1.recordedAt }
    let unit = sorted.first?.unit ?? "lbs"
    let current = sorted.first?.weight

    // 7-day change
    let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    let older = sorted.first { $0.recordedAt <= sevenDaysAgo }
    let change7d: Double? = {
        guard let c = current, let o = older?.weight else { return nil }
        return (c - o).rounded(to: 1)
    }()

    // Trend: compare last 3 entries
    let trend: WeightStats.Trend = {
        guard sorted.count >= 3 else { return .unknown }
        let a = sorted[2].weight
        let c = sorted[0].weight
        let slope = (c - a) / 2
        if slope > 0.1 { return .up }
        if slope < -0.1 { return .down }
        return .flat
    }()

    let weights = sorted.map { $0.weight }
    return WeightStats(
        current: current,
        change7d: change7d,
        trend: trend,
        min: weights.min(),
        max: weights.max(),
        unit: unit
    )
}

private extension Double {
    func rounded(to places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
