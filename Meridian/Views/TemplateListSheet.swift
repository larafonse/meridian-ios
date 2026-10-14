import SwiftUI
import SwiftData

struct TemplateListSheet: View {
    @Query(sort: \WorkoutTemplate.createdAt, order: .forward) private var templates: [WorkoutTemplate]
    @Query(sort: \TemplateWorkoutScore.date, order: .reverse) private var scores: [TemplateWorkoutScore]
    @Environment(\.modelContext) private var modelContext

    @State private var editingTemplate: WorkoutTemplate? = nil
    @State private var showingNewTemplate = false

    /// Templates sorted: those with scores first (most recently used), then by creation date.
    private var sortedTemplates: [WorkoutTemplate] {
        let recentTemplateIDs: [UUID] = {
            var seen = Set<UUID>()
            return scores.compactMap { score -> UUID? in
                guard !seen.contains(score.templateID) else { return nil }
                seen.insert(score.templateID)
                return score.templateID
            }
        }()

        let withScores = recentTemplateIDs.compactMap { id in
            templates.first(where: { $0.id == id })
        }
        let withoutScores = templates.filter { t in
            !recentTemplateIDs.contains(t.id)
        }
        return withScores + withoutScores
    }

    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "No Templates",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Tap + to create your first workout template.")
                    )
                } else {
                    List {
                        ForEach(sortedTemplates) { template in
                            Button {
                                editingTemplate = template
                            } label: {
                                TemplateTickerRow(template: template)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            for i in offsets { modelContext.delete(sortedTemplates[i]) }
                            try? modelContext.save()
                        }
                    }
                }
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewTemplate = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editingTemplate) { t in
                TemplateEditorSheet(template: t)
            }
            .sheet(isPresented: $showingNewTemplate) {
                TemplateEditorSheet(template: nil)
            }
        }
    }
}
