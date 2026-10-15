import SwiftUI
import SwiftData

@main
struct MeridianApp: App {
    // Declared static so it can be referenced in the @StateObject initializer
    private static let sharedContainer: ModelContainer = {
        try! ModelContainer(for: WeightEntry.self, WorkoutSession.self, Exercise.self, WorkoutSet.self, WorkoutTemplate.self, TemplateExercise.self, TemplateWorkoutScore.self, DashboardCard.self)
    }()

    @StateObject private var linker = WorkoutLinkerService(modelContainer: sharedContainer)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .environmentObject(linker)
        }
        .modelContainer(MeridianApp.sharedContainer)
    }
}
