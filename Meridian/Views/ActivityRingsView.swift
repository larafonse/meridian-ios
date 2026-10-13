import SwiftUI

struct ActivityRingsWidget: View {
    @State private var summary: ActivitySummary? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))

            HStack(spacing: 0) {
                RingCard(
                    title: "Move",
                    value: summary.map { Int($0.moveEnergy).formatted() } ?? "—",
                    goal: summary.map { Int($0.moveGoal).formatted() } ?? "—",
                    unit: "cal",
                    progress: summary?.moveProgress ?? 0,
                    color: Color(red: 1.0, green: 0.18, blue: 0.33)
                )
                .frame(maxWidth: .infinity)

                Divider().frame(height: 88)

                RingCard(
                    title: "Exercise",
                    value: summary.map { Int($0.exerciseMinutes).formatted() } ?? "—",
                    goal: summary.map { Int($0.exerciseGoal).formatted() } ?? "—",
                    unit: "min",
                    progress: summary?.exerciseProgress ?? 0,
                    color: Color(red: 0.38, green: 0.87, blue: 0.16)
                )
                .frame(maxWidth: .infinity)

                Divider().frame(height: 88)

                RingCard(
                    title: "Stand",
                    value: summary.map { Int($0.standHours).formatted() } ?? "—",
                    goal: summary.map { Int($0.standGoal).formatted() } ?? "—",
                    unit: "hrs",
                    progress: summary?.standProgress ?? 0,
                    color: Color(red: 0.12, green: 0.80, blue: 0.94)
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
        )
        .task {
            let service = HealthKitActivityService()
            do {
                try await service.requestAuthorization()
                summary = try await service.fetchTodaySummary()
            } catch {
                // HealthKit unavailable or denied — widget stays showing dashes
            }
        }
    }
}

private struct RingCard: View {
    let title: String
    let value: String
    let goal: String
    let unit: String
    let progress: Double
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            RingProgressView(progress: progress, color: color)
                .frame(width: 54, height: 54)

            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))

            Text("/ \(goal) \(unit)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct RingProgressView: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 7)
            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: progress)
        }
    }
}
