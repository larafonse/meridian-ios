import SwiftUI
import SwiftData
import UIKit

struct LogView: View {
    @Query(sort: \WeightEntry.recordedAt, order: .reverse) private var entries: [WeightEntry]
    @Environment(\.modelContext) private var modelContext

    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.961, green: 0.941, blue: 0.922, alpha: 1)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.black]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.black]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.961, green: 0.941, blue: 0.922)
                    .ignoresSafeArea()

                if entries.isEmpty {
                    emptyState
                } else {
                    entriesList
                }
            }
            .navigationTitle("Weight Log")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var emptyState: some View {
        Text("No entries yet.\nLog your first weight from the Dashboard.")
            .font(.system(size: 14))
            .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))
            .multilineTextAlignment(.center)
            .padding()
    }

    private var entriesList: some View {
        List {
            ForEach(entries) { entry in
                EntryRow(entry: entry)
                    .listRowBackground(Color.white)
                    .listRowSeparatorTint(Color(red: 0.898, green: 0.898, blue: 0.898))
            }
            .onDelete(perform: deleteEntries)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func deleteEntries(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(entries[index])
        }
    }
}

struct EntryRow: View {
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
