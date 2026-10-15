import Foundation
import SwiftData

@Model
final class DashboardCard {
    var name: String
    var statTickers: [String]
    var sortOrder: Int

    init(name: String, statTickers: [String], sortOrder: Int) {
        self.name = name
        self.statTickers = statTickers
        self.sortOrder = sortOrder
    }
}
