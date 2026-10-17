import Foundation
import SwiftData

@Model
final class MetricEntry {
    var id: UUID
    var metricID: UUID
    var metric: Metric
    var value: Double
    var recordedAt: Date
    var createdAt: Date

    init(metric: Metric, value: Double, recordedAt: Date) {
        self.id = UUID()
        self.metricID = metric.id
        self.metric = metric
        self.value = value
        self.recordedAt = recordedAt
        self.createdAt = .now
    }
}
