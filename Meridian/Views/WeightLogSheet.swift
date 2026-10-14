import SwiftUI
import SwiftData

struct WeightLogSheet: View {
    @Query(sort: \WeightEntry.recordedAt, order: .reverse) private var entries: [WeightEntry]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.961, green: 0.941, blue: 0.922)
                    .ignoresSafeArea()

                if entries.isEmpty {
                    Text("No entries yet.\nLog your first weight from the Dashboard.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    List {
                        ForEach(entries) { entry in
                            WeightEntryRow(entry: entry)
                                .listRowBackground(Color.white)
                                .listRowSeparatorTint(Color(red: 0.898, green: 0.898, blue: 0.898))
                        }
                        .onDelete(perform: deleteEntries)
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Weight Log")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
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

private struct WeightEntryRow: View {
    let entry: WeightEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.recordedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))
            }
            Spacer()
            Text("\(formatted(entry.weight)) \(entry.unit)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
        }
        .padding(.vertical, 4)
    }

    private func formatted(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
