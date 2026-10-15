import SwiftUI
import SwiftData

struct TemplateTickerRow: View {
    let template: WorkoutTemplate

    @Query private var scores: [TemplateWorkoutScore]

    init(template: WorkoutTemplate) {
        self.template = template
        let id = template.id
        self._scores = Query(
            filter: #Predicate<TemplateWorkoutScore> { $0.templateID == id },
            sort: \.date,
            order: .forward
        )
    }

    private var recentScores: [Double] {
        let raw = Array(scores.suffix(10).map { $0.totalVolume })
        return raw.count == 1 ? [0] + raw : raw
    }

    private var latestVolume: Double? {
        scores.last?.totalVolume
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(tickerSymbol(for: template.name))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                .frame(width: 44, alignment: .leading)

            Text(template.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))

            Spacer()

            if !recentScores.isEmpty {
                SparklineView(values: recentScores)
            }

            if let volume = latestVolume {
                Text(formatVolume(volume))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                    .frame(minWidth: 70, alignment: .trailing)
            } else {
                Text("--")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 70, alignment: .trailing)
            }
        }
        .padding(.vertical, 6)
    }

    private func formatVolume(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let formatted = formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        return "\(formatted) lbs"
    }
}
