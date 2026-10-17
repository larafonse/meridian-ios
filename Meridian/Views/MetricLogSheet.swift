import SwiftUI
import SwiftData

struct MetricLogSheet: View {
    let metric: Metric

    @Query private var entries: [MetricEntry]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingAdd = false

    init(metric: Metric) {
        self.metric = metric
        let id = metric.id
        _entries = Query(
            filter: #Predicate<MetricEntry> { $0.metricID == id },
            sort: \MetricEntry.recordedAt,
            order: .reverse
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.961, green: 0.941, blue: 0.922)
                    .ignoresSafeArea()

                if entries.isEmpty {
                    Text("No entries yet.\nUse Add to log your first \(metric.name) reading.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    List {
                        ForEach(entries) { entry in
                            MetricEntryRow(entry: entry, metric: metric)
                                .listRowBackground(Color.white)
                                .listRowSeparatorTint(Color(red: 0.898, green: 0.898, blue: 0.898))
                        }
                        .onDelete(perform: deleteEntries)
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle(metric.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add") { showingAdd = true }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddMetricEntrySheet(metric: metric)
            }
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(entries[index])
        }
        try? modelContext.save()
    }
}

private struct MetricEntryRow: View {
    let entry: MetricEntry
    let metric: Metric

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.recordedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))
            }
            Spacer()
            Text("\(formatted(entry.value)) \(metric.unit)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
        }
        .padding(.vertical, 4)
    }

    private func formatted(_ value: Double) -> String {
        if metric.valueType == .integer {
            return "\(Int(value.rounded()))"
        }
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
