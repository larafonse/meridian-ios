import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    let workout: WorkoutSession
    @ObservedObject var service: WorkoutSessionService
    let onMinimize: () -> Void
    let onEnd: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer? = nil
    @State private var newExerciseName: String = ""
    @State private var showingAddExercise = false
    @State private var isEnding = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Stats header
                HStack(spacing: 0) {
                    statCell(label: "Time", value: formatElapsed(elapsed))
                    Divider().frame(height: 50)
                    statCell(label: "BPM", value: service.currentBPM.map { "\($0)" } ?? "—")
                }
                .padding(.vertical, 12)
                .background(Color(red: 0.961, green: 0.941, blue: 0.922))

                Divider()

                // Exercise list
                List {
                    let sortedExercises = workout.exercises.sorted { $0.order < $1.order }
                    ForEach(sortedExercises) { exercise in
                        Section {
                            let sortedSets = exercise.sets.sorted { $0.order < $1.order }
                            ForEach(sortedSets) { set in
                                SetRow(set: set)
                            }
                            .onDelete { offsets in
                                deleteSets(offsets, from: exercise, sortedSets: sortedSets)
                            }

                            Button {
                                addSet(to: exercise)
                            } label: {
                                Label("Add Set", systemImage: "plus")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.blue)
                            }
                        } header: {
                            Text(exercise.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                        }
                    }
                    .onDelete { offsets in
                        deleteExercises(offsets, sortedExercises: sortedExercises)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle(workout.label.isEmpty ? workout.workoutTypeDisplayName : workout.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Minimize") { onMinimize() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await endWorkout() }
                    } label: {
                        if isEnding {
                            ProgressView()
                        } else {
                            Text("End")
                                .foregroundStyle(.red)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isEnding)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        showingAddExercise = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                    }
                }
            }
            .alert("Add Exercise", isPresented: $showingAddExercise) {
                TextField("Exercise name", text: $newExerciseName)
                Button("Add") { addExercise() }
                Button("Cancel", role: .cancel) { newExerciseName = "" }
            }
        }
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
    }

    // MARK: - Stats header

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Timer

    private func startTimer() {
        elapsed = Date().timeIntervalSince(workout.startedAt)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsed = Date().timeIntervalSince(workout.startedAt)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func formatElapsed(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: - Exercise / Set mutations

    private func addExercise() {
        let name = newExerciseName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let exercise = Exercise(name: name, order: workout.exercises.count)
        modelContext.insert(exercise)
        workout.exercises.append(exercise)
        newExerciseName = ""
    }

    private func deleteExercises(_ offsets: IndexSet, sortedExercises: [Exercise]) {
        for i in offsets {
            modelContext.delete(sortedExercises[i])
        }
    }

    private func addSet(to exercise: Exercise) {
        let sorted = exercise.sets.sorted { $0.order < $1.order }
        let lastWeight = sorted.last?.weight ?? 0
        let lastUnit = sorted.last?.unit ?? "lbs"
        let set = WorkoutSet(reps: 0, weight: lastWeight, unit: lastUnit, order: exercise.sets.count)
        modelContext.insert(set)
        exercise.sets.append(set)
    }

    private func deleteSets(_ offsets: IndexSet, from exercise: Exercise, sortedSets: [WorkoutSet]) {
        for i in offsets {
            modelContext.delete(sortedSets[i])
        }
    }

    // MARK: - End workout

    private func endWorkout() async {
        isEnding = true
        let hkUUID = try? await service.finish()
        workout.endedAt = Date()
        workout.healthKitUUID = hkUUID
        try? modelContext.save()
        isEnding = false
        onEnd()
    }
}

// MARK: - SetRow

private struct SetRow: View {
    @Bindable var set: WorkoutSet

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                TextField("0", value: $set.reps, format: .number)
                    .keyboardType(.numberPad)
                    .frame(width: 44)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                Text("reps")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                TextField("0", value: $set.weight, format: .number)
                    .keyboardType(.decimalPad)
                    .frame(width: 60)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $set.unit) {
                    Text("lbs").tag("lbs")
                    Text("kg").tag("kg")
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }
}
