import Foundation
import SwiftData

enum ValueType: String, Codable, CaseIterable {
    case integer
    case decimal
}

@Model
final class Metric {
    var id: UUID
    var name: String
    var valueType: ValueType
    var unit: String
    var createdAt: Date
    var sortOrder: Int
    @Relationship(deleteRule: .cascade, inverse: \MetricEntry.metric)
    var entries: [MetricEntry] = []

    init(name: String, valueType: ValueType, unit: String, sortOrder: Int) {
        self.id = UUID()
        self.name = name
        self.valueType = valueType
        self.unit = unit
        self.sortOrder = sortOrder
        self.createdAt = .now
        self.entries = []
    }
}
