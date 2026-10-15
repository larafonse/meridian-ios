import SwiftUI
import SwiftData
import Charts

// MARK: - Volume Stats (file-scope for testability)

struct TemplateVolumeStats {
    let total: Int
    let best: Double?
    let avg: Double?
}

func volumeStats(from scores: [TemplateWorkoutScore]) -> TemplateVolumeStats {
    guard !scores.isEmpty else {
        return TemplateVolumeStats(total: 0, best: nil, avg: nil)
    }
    let volumes = scores.map(\.totalVolume)
    return TemplateVolumeStats(
        total: scores.count,
        best: volumes.max(),
        avg: volumes.reduce(0, +) / Double(scores.count)
    )
}

// MARK: - Placeholder (will be filled in Task 2)

struct TemplateDetailSheet: View {
    let template: WorkoutTemplate
    var body: some View { EmptyView() }
}
