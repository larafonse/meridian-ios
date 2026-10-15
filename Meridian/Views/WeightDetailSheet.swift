import SwiftUI
import SwiftData

struct WeightDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WeightEntry.recordedAt, order: .reverse) private var entries: [WeightEntry]
    @State private var showingLog = false

    var body: some View {
        NavigationStack {
            ScrollView {
                WeightChartView(entries: entries)
                    .padding(16)
            }
            .background(Color(red: 0.961, green: 0.941, blue: 0.922).ignoresSafeArea())
            .navigationTitle("Body Weight")
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
            WeightLogSheet()
        }
    }
}
