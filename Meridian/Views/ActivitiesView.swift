import SwiftUI
import SwiftData
import HealthKit

struct ActivitiesView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var allSessions: [WorkoutSession]
    @Environment(\.modelContext) private var modelContext

    @State private var hkWorkouts: [HKWorkout] = []
    @State private var isLoading = true
    @State private var selectedItem: WorkoutListItem? = nil
    @State private var showingTemplates = false

    private var mergedItems: [WorkoutListItem] {
        WorkoutListItem.merge(sessions: allSessions, hkWorkouts: hkWorkouts)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.961, green: 0.941, blue: 0.922)
                    .ignoresSafeArea()

                if isLoading {
                    ProgressView()
                } else if mergedItems.isEmpty {
                    Text("No workouts yet.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))
                } else {
                    List {
                        ForEach(mergedItems) { item in
                            WorkoutItemRow(item: item)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedItem = item }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if item.session != nil {
                                        Button(role: .destructive) {
                                            deleteSession(for: item)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                                .listRowBackground(Color.white)
                                .listRowSeparatorTint(Color(red: 0.898, green: 0.898, blue: 0.898))
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .refreshable { await loadWorkouts() }
                }
            }
            .navigationTitle("Activities")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Templates") { showingTemplates = true }
                        .font(.system(size: 15))
                        .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                }
            }
            .sheet(item: $selectedItem) { item in
                WorkoutLogSheet(session: item.session, hkWorkout: item.hkWorkout)
            }
            .sheet(isPresented: $showingTemplates) {
                TemplateListSheet()
            }
        }
        .task { await loadWorkouts() }
    }

    private func loadWorkouts() async {
        isLoading = true
        hkWorkouts = (try? await HealthKitWorkoutService().fetchAllWorkouts()) ?? []
        isLoading = false
    }

    private func deleteSession(for item: WorkoutListItem) {
        guard let session = item.session else { return }
        modelContext.delete(session)
        try? modelContext.save()
    }
}
