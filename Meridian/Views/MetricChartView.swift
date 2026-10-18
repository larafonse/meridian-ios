import SwiftUI
import Charts

struct MetricChartView: View {
    let entries: [MetricEntry]
    let metric: Metric

    @State private var selectedEntry: MetricEntry? = nil

    private var stats: MetricStats { computeMetricStats(entries: entries, metric: metric) }

    private var chartData: [MetricEntry] {
        Array(entries.sorted { $0.recordedAt < $1.recordedAt }.suffix(7))
    }

    private var lineData: [MetricEntry] {
        Array(entries.sorted { $0.recordedAt < $1.recordedAt }.suffix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statsRow
            if chartData.isEmpty || lineData.count < 2 {
                Text("No data for this range yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
            } else {
                chart
                    .frame(height: 80)
            }
        }
    }

    // MARK: Stats Row

    private var statsRow: some View {
        HStack(alignment: .top, spacing: 0) {
            statItem(label: "CURRENT", value: formattedValue(stats.current, unit: stats.unit))
            statItem(label: "7-DAY CHANGE", value: formattedChange(stats.change7d, unit: stats.unit))
            Spacer()
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))
                .tracking(0.4)
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(minWidth: 0, alignment: .leading)
        .padding(.trailing, 16)
    }

    // MARK: Chart

    private var chart: some View {
        Chart {
            ForEach(lineData) { entry in
                LineMark(
                    x: .value("Date", entry.recordedAt, unit: .day),
                    y: .value("Value", entry.value)
                )
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                .interpolationMethod(.catmullRom)
            }
            ForEach(chartData) { entry in
                PointMark(
                    x: .value("Date", entry.recordedAt, unit: .day),
                    y: .value("Value", entry.value)
                )
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                .symbolSize(selectedEntry?.id == entry.id ? 60 : 25)

                if let selected = selectedEntry, selected.id == entry.id {
                    RuleMark(x: .value("Date", selected.recordedAt, unit: .day))
                        .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04).opacity(0.2))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .annotation(position: .top, spacing: 4) {
                            callout(for: selected)
                        }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Color(red: 0.898, green: 0.898, blue: 0.898))
            }
        }
        .chartXScale(domain: {
            let start = lineData.first?.recordedAt ?? .now
            let last = lineData.last?.recordedAt ?? .now
            let end = Calendar.current.date(byAdding: .day, value: 3, to: last) ?? last
            return start...end
        }())
        .chartYScale(domain: {
            let vals = lineData.map(\.value)
            let padding = metric.valueType == .integer ? 5.0 : 1.0
            let min = (vals.min() ?? 0) - padding
            let max = (vals.max() ?? 0) + padding
            return min...max
        }())
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Color(red: 0.898, green: 0.898, blue: 0.898))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { _ in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let date: Date = proxy.value(atX: value.location.x) else { return }
                                selectedEntry = chartData.min(by: {
                                    abs($0.recordedAt.timeIntervalSince(date)) < abs($1.recordedAt.timeIntervalSince(date))
                                })
                            }
                            .onEnded { _ in selectedEntry = nil }
                    )
            }
        }
    }

    // MARK: Callout

    private func callout(for entry: MetricEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.recordedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 10))
                .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))
            Text("\(formatted(entry.value)) \(metric.unit)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    // MARK: Helpers

    private func formattedValue(_ value: Double?, unit: String) -> String {
        guard let v = value else { return "—" }
        return "\(formatted(v)) \(unit)"
    }

    private func formattedChange(_ value: Double?, unit: String) -> String {
        guard let v = value else { return "—" }
        let prefix = v > 0 ? "+" : ""
        return "\(prefix)\(formatted(v)) \(unit)"
    }

    private func formatted(_ value: Double) -> String {
        if metric.valueType == .integer {
            return "\(Int(value.rounded()))"
        }
        let f = NumberFormatter()
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
