import SwiftUI
import SwiftData

struct MetricDetailSheet: View {
    let metric: Metric

    @Query private var entries: [MetricEntry]
    @Environment(\.dismiss) private var dismiss
    @State private var showingLog = false

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
            ScrollView {
                MetricChartView(entries: entries, metric: metric)
                    .padding(16)
            }
            .background(Color(red: 0.961, green: 0.941, blue: 0.922).ignoresSafeArea())
            .navigationTitle(metric.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Log") { showingLog = true }
                }
            }
        }
        .sheet(isPresented: $showingLog) {
            MetricLogSheet(metric: metric)
        }
    }
}
