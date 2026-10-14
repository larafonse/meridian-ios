import SwiftUI

struct StepsDistanceCardView: View {
    let stepCount: Int
    let distanceMeters: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statItem(label: "STEPS", value: formattedSteps)
            statItem(label: "DISTANCE", value: formattedDistance)
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))
                .tracking(0.4)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }

    private var formattedSteps: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: stepCount)) ?? "\(stepCount)"
    }

    private var formattedDistance: String {
        let usesMetric = Locale.current.measurementSystem != .us
        if usesMetric {
            let km = distanceMeters / 1000
            return String(format: "%.2f km", km)
        } else {
            let miles = distanceMeters / 1609.344
            return String(format: "%.2f mi", miles)
        }
    }
}
