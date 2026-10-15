import SwiftUI
import SwiftData

struct TemplatesPortfolioCard: View {
    let onTapAll: () -> Void
    let onTapTemplate: (WorkoutTemplate) -> Void

    @Query(sort: \TemplateWorkoutScore.date, order: .reverse) private var scores: [TemplateWorkoutScore]
    @Query(sort: \WorkoutTemplate.createdAt, order: .forward) private var templates: [WorkoutTemplate]

    /// Up to 3 most recently used templates, in order of last use.
    private var topTemplates: [WorkoutTemplate] {
        var seen = Set<UUID>()
        let recentIDs = scores.compactMap { score -> UUID? in
            guard !seen.contains(score.templateID) else { return nil }
            seen.insert(score.templateID)
            return score.templateID
        }.prefix(3)

        return recentIDs.compactMap { id in
            templates.first(where: { $0.id == id })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTapAll) {
                HStack {
                    Text("Templates")
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

            if topTemplates.isEmpty {
                Text("Complete a workout from a template to see your history here.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(topTemplates) { template in
                        Button { onTapTemplate(template) } label: {
                            TemplateTickerRow(template: template)
                        }
                        .buttonStyle(.plain)

                        if template.id != topTemplates.last?.id {
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
