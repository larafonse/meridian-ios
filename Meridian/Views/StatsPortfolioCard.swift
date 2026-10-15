import SwiftUI

struct StatsPortfolioCard: View {
    let items: [StatItem]
    let title: String
    let onTapAll: (() -> Void)?
    let onTapStat: (StatItem) -> Void
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    init(
        items: [StatItem],
        title: String = "Stats",
        onTapAll: (() -> Void)? = nil,
        onTapStat: @escaping (StatItem) -> Void,
        onEdit: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.items = items
        self.title = title
        self.onTapAll = onTapAll
        self.onTapStat = onTapStat
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    var body: some View {
        cardContent
            .contextMenu {
                if let onEdit {
                    Button { onEdit() } label: {
                        Label("Edit Card", systemImage: "pencil")
                    }
                }
                if let onDelete {
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Remove Card", systemImage: "trash")
                    }
                }
            }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let onTapAll {
                Button(action: onTapAll) {
                    HStack {
                        Text(title)
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
            } else {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }

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
