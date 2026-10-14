import Foundation
import SwiftData

@Model
final class TemplateWorkoutScore {
    var id: UUID
    var templateID: UUID
    var templateName: String
    var sessionID: UUID
    var date: Date
    var totalVolume: Double

    init(templateID: UUID, templateName: String, sessionID: UUID, date: Date, totalVolume: Double) {
        self.id = UUID()
        self.templateID = templateID
        self.templateName = templateName
        self.sessionID = sessionID
        self.date = date
        self.totalVolume = totalVolume
    }
}
