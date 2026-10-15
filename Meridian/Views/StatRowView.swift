import SwiftUI

struct StatRowView: View {
    let item: StatItem

    var body: some View {
        HStack(spacing: 12) {
            Text(item.ticker)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                .frame(width: 44, alignment: .leading)

            Text(item.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))

            Spacer()

            SparklineView(values: item.sparklineData)

            Text(item.latestValue)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(item.latestValue == "--"
                    ? .secondary
                    : Color(red: 0.04, green: 0.04, blue: 0.04))
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
}
