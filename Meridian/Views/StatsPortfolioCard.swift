import SwiftUI

struct StatsPortfolioCard: View {
    let items: [StatItem]
    let onTapAll: () -> Void
    let onTapStat: (StatItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTapAll) {
                HStack {
                    Text("Stats")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            }
            .buttonStyle(.plain)

            if items.isEmpty {
                Text("Complete a workout from a template to see your history here.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        Button { onTapStat(item) } label: {
                            StatRowView(item: item)
                        }
                        .buttonStyle(.plain)

                        if item.id != items.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
        )
    }
}
