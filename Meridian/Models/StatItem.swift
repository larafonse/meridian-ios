import Foundation

struct StatItem: Identifiable {
    let id: UUID
    let ticker: String
    let name: String
    let sparklineData: [Double]
    let latestValue: String
    let detail: StatDetail
}

enum StatDetail {
    case template(WorkoutTemplate)
    case weight
}

// MARK: - Weight builder

extension StatItem {
    private static let weightID = UUID()
    private static let weightFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    static func forWeight(entries: [WeightEntry]) -> StatItem {
        let sorted = entries.sorted { $0.recordedAt < $1.recordedAt }
        let raw = Array(sorted.suffix(10).map { $0.weight })
        let sparkline: [Double] = raw.isEmpty ? [0, 0] : (raw.count == 1 ? [0] + raw : raw)
        let latestValue: String = {
            guard let last = sorted.last else { return "--" }
            let formatted = weightFormatter.string(from: NSNumber(value: last.weight)) ?? "\(last.weight)"
            return "\(formatted) \(last.unit)"
        }()
        return StatItem(id: weightID, ticker: "WGHT", name: "Body Weight",
                        sparklineData: sparkline, latestValue: latestValue, detail: .weight)
    }
}

// MARK: - Template builder

extension StatItem {
    private static let volumeFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    static func forTemplate(_ template: WorkoutTemplate, scores: [TemplateWorkoutScore]) -> StatItem {
        let sorted = scores
            .filter { $0.templateID == template.id }
            .sorted { $0.date < $1.date }
        let raw = Array(sorted.suffix(10).map { $0.totalVolume })
        let sparkline: [Double] = raw.isEmpty ? [0, 0] : (raw.count == 1 ? [0] + raw : raw)
        let latestValue: String = {
            guard let last = sorted.last else { return "--" }
            let formatted = volumeFormatter.string(from: NSNumber(value: last.totalVolume)) ?? "\(Int(last.totalVolume))"
            return "\(formatted) lbs"
        }()
        return StatItem(
            id: template.id,
            ticker: tickerSymbol(for: template.name),
            name: template.name,
            sparklineData: sparkline,
            latestValue: latestValue,
            detail: .template(template)
        )
    }
}
