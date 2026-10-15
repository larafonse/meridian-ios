import SwiftUI
import SwiftData

struct CardEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let availableStats: [StatItem]
    let existingCard: DashboardCard?
    let nextSortOrder: Int

    @State private var name: String
    @State private var selectedTickers: Set<String>

    init(availableStats: [StatItem], existingCard: DashboardCard?, nextSortOrder: Int) {
        self.availableStats = availableStats
        self.existingCard = existingCard
        self.nextSortOrder = nextSortOrder
        _name = State(initialValue: existingCard?.name ?? "")
        _selectedTickers = State(initialValue: Set(existingCard?.statTickers ?? []))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Card Name") {
                    TextField("e.g. Upper Body", text: $name)
                }
                Section("Stats") {
                    ForEach(availableStats) { stat in
                        Toggle(isOn: Binding(
                            get: { selectedTickers.contains(stat.ticker) },
                            set: { on in
                                if on { selectedTickers.insert(stat.ticker) }
                                else { selectedTickers.remove(stat.ticker) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stat.name)
                                Text(stat.latestValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(existingCard == nil ? "New Card" : "Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selectedTickers.isEmpty)
                }
            }
        }
    }

    private func save() {
        // Preserve the order stats appear in availableStats
        let tickers = availableStats
            .filter { selectedTickers.contains($0.ticker) }
            .map(\.ticker)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let card = existingCard {
            card.name = trimmedName
            card.statTickers = tickers
        } else {
            let card = DashboardCard(name: trimmedName, statTickers: tickers, sortOrder: nextSortOrder)
            modelContext.insert(card)
        }
        dismiss()
    }
}
