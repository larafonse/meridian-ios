import SwiftUI
import SwiftData
import Charts

// MARK: - Volume Stats (file-scope for testability)

struct TemplateVolumeStats {
    let total: Int
    let best: Double?
    let avg: Double?
}

func volumeStats(from scores: [TemplateWorkoutScore]) -> TemplateVolumeStats {
    guard !scores.isEmpty else {
        return TemplateVolumeStats(total: 0, best: nil, avg: nil)
    }
    let volumes = scores.map(\.totalVolume)
    return TemplateVolumeStats(
        total: scores.count,
        best: volumes.max(),
        avg: volumes.reduce(0, +) / Double(scores.count)
    )
}

// MARK: - TemplateDetailSheet

struct TemplateDetailSheet: View {
    let template: WorkoutTemplate

    @Query private var scores: [TemplateWorkoutScore]
    @State private var showingEditor = false
    @Environment(\.dismiss) private var dismiss

    init(template: WorkoutTemplate) {
        self.template = template
        let id = template.id
        self._scores = Query(
            filter: #Predicate<TemplateWorkoutScore> { $0.templateID == id },
            sort: \.date,
            order: .forward
        )
    }

    private var stats: TemplateVolumeStats { volumeStats(from: scores) }

    private var chartColor: Color {
        guard let first = scores.first?.totalVolume,
              let last = scores.last?.totalVolume else { return .green }
        return last >= first ? .green : .red
    }

    private var sortedExercises: [TemplateExercise] {
        template.exercises.sorted { $0.order < $1.order }
    }

    private var reversedScores: [TemplateWorkoutScore] {
        Array(scores.reversed())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if scores.count >= 2 {
                        chartSection
                    } else if scores.isEmpty {
                        Text("Complete a workout from this template to see your history here.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    if stats.total > 0 {
                        statsSection
                    }

                    if !sortedExercises.isEmpty {
                        exercisesSection
                    }

                    historySection
                }
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .navigationTitle(template.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { showingEditor = true }
                }
            }
            .sheet(isPresented: $showingEditor) {
                TemplateEditorSheet(template: template)
            }
        }
    }

    // MARK: - Chart

    private var chartSection: some View {
        Chart {
            ForEach(scores) { score in
                AreaMark(
                    x: .value("Date", score.date),
                    y: .value("Volume", score.totalVolume)
                )
                .foregroundStyle(chartColor.opacity(0.15))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", score.date),
                    y: .value("Volume", score.totalVolume)
                )
                .foregroundStyle(chartColor)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel()
                AxisGridLine()
            }
        }
        .frame(height: 180)
        .padding(.horizontal)
    }

    // MARK: - Stats

    private var statsSection: some View {
        HStack(spacing: 0) {
            statChip(label: "Sessions", value: "\(stats.total)")
            Divider().frame(height: 40)
            statChip(label: "Best", value: stats.best.map { formatVolume($0) } ?? "--")
            Divider().frame(height: 40)
            statChip(label: "Avg", value: stats.avg.map { formatVolume($0) } ?? "--")
        }
        .padding(.horizontal)
    }

    private func statChip(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Exercises

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exercises")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(Array(sortedExercises.enumerated()), id: \.element.id) { index, exercise in
                    HStack {
                        Text(exercise.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                        Spacer()
                        if let reps = exercise.defaultReps, let weight = exercise.defaultWeight {
                            Text("\(reps) × \(formatWeight(weight, unit: exercise.defaultWeightUnit))")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)

                    if index < sortedExercises.count - 1 {
                        Divider().padding(.leading)
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if reversedScores.isEmpty {
                Text("No sessions yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(reversedScores.enumerated()), id: \.element.id) { index, score in
                        HStack {
                            Text(score.date, style: .date)
                                .font(.system(size: 14))
                                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                            Spacer()
                            Text(formatVolume(score.totalVolume))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)

                        if index < reversedScores.count - 1 {
                            Divider().padding(.leading)
                        }
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
                )
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Formatting

    private func formatVolume(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return "\(formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))") lbs"
    }

    private func formatWeight(_ value: Double, unit: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return "\(formatter.string(from: NSNumber(value: value)) ?? "\(value)") \(unit)"
    }
}
