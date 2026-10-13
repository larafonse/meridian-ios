import SwiftUI
import SwiftData

@main
struct MeridianApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
        }
        .modelContainer(for: [WeightEntry.self, WorkoutSession.self, Exercise.self, WorkoutSet.self])
    }
}
