import SwiftUI
import SwiftData

struct CreateMetricSheet: View {
    let nextSortOrder: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var valueType: ValueType = .decimal
    @State private var unit = ""
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.961, green: 0.941, blue: 0.922)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Name")
                                .font(.system(size: 15))
                                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                            Spacer()
                            TextField("e.g. Systolic", text: $name)
                                .autocorrectionDisabled()
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 15))
                                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                        }
                        .padding(16)

                        Divider()
                            .background(Color(red: 0.898, green: 0.898, blue: 0.898))

                        HStack {
                            Text("Type")
                                .font(.system(size: 15))
                                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                            Spacer()
                            Picker("Type", selection: $valueType) {
                                Text("Integer").tag(ValueType.integer)
                                Text("Decimal").tag(ValueType.decimal)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 150)
                        }
                        .padding(16)

                        Divider()
                            .background(Color(red: 0.898, green: 0.898, blue: 0.898))

                        HStack {
                            Text("Unit")
                                .font(.system(size: 15))
                                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                            Spacer()
                            TextField("e.g. mmHg", text: $unit)
                                .autocorrectionDisabled()
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 15))
                                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                        }
                        .padding(16)
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
                    )

                    if showingError {
                        Text("Please enter a name and unit.")
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .navigationTitle("New Metric")
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
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedUnit.isEmpty else {
            showingError = true
            return
        }
        let m = Metric(name: trimmedName, valueType: valueType, unit: trimmedUnit, sortOrder: nextSortOrder)
        modelContext.insert(m)
        dismiss()
    }
}
