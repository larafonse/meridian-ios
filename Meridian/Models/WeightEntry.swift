import Foundation
import SwiftData

@Model
final class WeightEntry {
    var id: UUID
    var weight: Double
    var unit: String
    var recordedAt: Date
    var createdAt: Date

    init(weight: Double, unit: String, recordedAt: Date = .now) {
        self.id = UUID()
        self.weight = weight
        self.unit = unit
        self.recordedAt = recordedAt
        self.createdAt = .now
    }
}
