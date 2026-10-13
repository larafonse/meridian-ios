import SwiftUI
import SwiftData

struct TemplateListSheet: View {
    @Query(sort: \WorkoutTemplate.createdAt, order: .forward) private var templates: [WorkoutTemplate]
    @Environment(\.modelContext) private var modelContext

    @State private var editingTemplate: WorkoutTemplate? = nil
    @State private var showingNewTemplate = false

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
                        ForEach(templates) { template in
                            Button {
                                editingTemplate = template
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(template.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                                    Text("\(template.workoutTypeDisplayName) · \(template.exercises.count) exercises")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets { modelContext.delete(templates[i]) }
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
