import SwiftUI
import SwiftData

struct AddMetricEntrySheet: View {
    let metric: Metric

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var valueText = ""
    @State private var recordedAt = Date.now
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.961, green: 0.941, blue: 0.922)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Value")
                                .font(.system(size: 15))
                                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                            Spacer()
                            TextField("0", text: $valueText)
                                .keyboardType(metric.valueType == .integer ? .numberPad : .decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                                .frame(width: 100)
                            Text(metric.unit)
                                .font(.system(size: 15))
                                .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))
                        }
                        .padding(16)

                        Divider()
                            .background(Color(red: 0.898, green: 0.898, blue: 0.898))

                        DatePicker(
                            "Date",
                            selection: $recordedAt,
                            in: ...Date.now,
                            displayedComponents: .date
                        )
                        .font(.system(size: 15))
                        .padding(16)
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
                    )

                    if showingError {
                        Text("Please enter a valid number greater than 0.")
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .navigationTitle("Add Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                }
            }
        }
    }

    private func save() {
        let trimmed = valueText.trimmingCharacters(in: .whitespaces)
        guard let raw = Double(trimmed), raw > 0 else {
            showingError = true
            return
        }
        let value = metric.valueType == .integer ? raw.rounded() : raw
        let entry = MetricEntry(metric: metric, value: value, recordedAt: recordedAt)
        modelContext.insert(entry)
        dismiss()
    }
}
