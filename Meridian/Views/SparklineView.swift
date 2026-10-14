import SwiftUI
import Charts

// MARK: - Ticker symbol

/// Generates a stock-ticker-style abbreviation from a template name.
/// Exposed at file scope for testability.
func tickerSymbol(for name: String) -> String {
    let words = name.trimmingCharacters(in: .whitespaces)
        .components(separatedBy: .whitespaces)
        .filter { !$0.isEmpty }
    if words.count > 1 {
        return String(words.prefix(4).compactMap { $0.first }.map { Character($0.uppercased()) })
    } else {
        return String(name.trimmingCharacters(in: .whitespaces).prefix(4)).uppercased()
    }
}

// MARK: - SparklineView

struct SparklineView: View {
    let values: [Double]

    private var color: Color {
        guard let first = values.first, let last = values.last else { return .green }
        return last >= first ? .green : .red
    }

    var body: some View {
        if values.isEmpty {
            EmptyView()
        } else {
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    LineMark(
                        x: .value("Session", index),
                        y: .value("Volume", value)
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(width: 60, height: 30)
        }
    }
}
