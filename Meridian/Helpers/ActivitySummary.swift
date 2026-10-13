import Foundation

struct ActivitySummary {
    let moveEnergy: Double
    let moveGoal: Double
    let exerciseMinutes: Double
    let exerciseGoal: Double
    let standHours: Double
    let standGoal: Double

    var moveProgress: Double {
        guard moveGoal > 0 else { return 0 }
        return moveEnergy / moveGoal
    }

    var exerciseProgress: Double {
        guard exerciseGoal > 0 else { return 0 }
        return exerciseMinutes / exerciseGoal
    }

    var standProgress: Double {
        guard standGoal > 0 else { return 0 }
        return standHours / standGoal
    }
}
