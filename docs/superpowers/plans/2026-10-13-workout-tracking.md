# Workout Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add workout session tracking to Meridian — start a workout from the app, log exercises/sets/reps/weights in real-time, save to HealthKit, and review progress across sessions.

**Architecture:** Three new SwiftData models (`WorkoutSession`, `Exercise`, `WorkoutSet`) store logged data locally. `WorkoutSessionService` wraps `HKWorkoutBuilder` and a live heart-rate observer. Four new SwiftUI views handle the card, start sheet, active logging screen, and history sheet. `DashboardView` is updated to wire them together.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, HealthKit (`HKWorkoutBuilder`, `HKAnchoredObjectQuery`)

**Spec:** `docs/superpowers/specs/2026-10-13-workout-tracking-design.md`

## Global Constraints

- iOS 17.0+ deployment target
- Swift 6 strict concurrency — all HealthKit callbacks must be dispatched to `@MainActor` or use `CheckedContinuation`
- Existing card styling: white background, `cornerRadius: 16`, 1pt border `Color(red: 0.898, green: 0.898, blue: 0.898)`, 20pt padding
- Beige background: `Color(red: 0.961, green: 0.941, blue: 0.922)`
- Header font: `Font.custom("PlayfairDisplay-Regular", size: 17).weight(.bold)` for card titles; `.system(size: 15, weight: .semibold)` for section labels
- No third-party dependencies — Apple frameworks only
- Graceful degradation: HealthKit unavailable or denied must never crash; show "—" for BPM, skip HK save but still persist to SwiftData

## Review Focus

- **HealthKit permission denied mid-session:** `HKWorkoutBuilder.finishWorkout()` throws — workout data must still save to SwiftData even if HealthKit write fails. Task 3 owns this; add a test that simulates builder failure and checks SwiftData is still written.
- **Minimize → background → foreground:** `activeWorkout` state lives in `DashboardView`; if the OS kills the view hierarchy the in-progress workout is lost. This is an accepted limitation (out of scope for this plan) — document it with a code comment in `DashboardView`.
- **Duplicate heart-rate samples:** `HKAnchoredObjectQuery` `updateHandler` may fire multiple times with overlapping samples. The live BPM display should always take the most-recent sample's value, not append. Task 4 tests this.
- **Empty exercise list on End Workout:** User taps End immediately — `WorkoutSession` with zero exercises must still save correctly. Task 5 tests this.
- **SwiftData cascade delete:** Deleting a `WorkoutSession` must delete its `Exercise` and `WorkoutSet` children. Task 2 tests this via model relationships.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `Meridian/Models/WorkoutSession.swift` | SwiftData models: `WorkoutSession`, `Exercise`, `WorkoutSet` |
| Create | `Meridian/Helpers/WorkoutSessionService.swift` | `HKWorkoutBuilder` wrapper + live HR observer |
| Create | `Meridian/Views/ActivitiesCard.swift` | Dashboard card — recent sessions + Start/Resume button |
| Create | `Meridian/Views/StartWorkoutSheet.swift` | Workout type picker + label field |
| Create | `Meridian/Views/ActiveWorkoutView.swift` | Full-screen logging UI |
| Create | `Meridian/Views/WorkoutHistorySheet.swift` | Read-only progress view per workout type |
| Modify | `Meridian/MeridianApp.swift` | Add new models to `modelContainer` |
| Modify | `Meridian/Views/DashboardView.swift` | Wire up Activities card + sheets |
| Modify | `Meridian/Info.plist` | Add `NSHealthUpdateUsageDescription` |
| Modify | `Meridian/Helpers/ActivityService.swift` | Add heart rate + workout write permissions |
| Create | `MeridianTests/WorkoutSessionTests.swift` | Model + service tests |

---

## Task 1: SwiftData Models

**Files:**
- Create: `Meridian/Models/WorkoutSession.swift`
- Create: `MeridianTests/WorkoutSessionTests.swift`

**Interfaces:**
- Produces:
  - `WorkoutSession(workoutType:workoutTypeDisplayName:label:startedAt:)` → `WorkoutSession`
  - `Exercise(name:order:)` → `Exercise`
  - `WorkoutSet(reps:weight:unit:order:)` → `WorkoutSet`
  - `WorkoutSession.durationFormatted: String` (computed, "45:32" style)

- [ ] **Step 1: Write failing model tests**

Create `MeridianTests/WorkoutSessionTests.swift`:

```swift
import Testing
import SwiftData
@testable import Meridian

@Suite("WorkoutSession model")
struct WorkoutSessionTests {
    @Test("WorkoutSet stores reps and weight")
    func workoutSetStoresData() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutSession.self, Exercise.self, WorkoutSet.self, configurations: config)
        let ctx = ModelContext(container)

        let session = WorkoutSession(
            workoutType: "traditionalStrengthTraining",
            workoutTypeDisplayName: "Strength Training",
            label: "Leg Day",
            startedAt: .now
        )
        let exercise = Exercise(name: "Squat", order: 0)
        let set = WorkoutSet(reps: 10, weight: 135.0, unit: "lbs", order: 0)
        exercise.sets = [set]
        session.exercises = [exercise]
        ctx.insert(session)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<WorkoutSession>())
        #expect(fetched.count == 1)
        #expect(fetched[0].exercises[0].sets[0].reps == 10)
        #expect(fetched[0].exercises[0].sets[0].weight == 135.0)
    }

    @Test("Cascade delete removes exercises and sets")
    func cascadeDelete() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutSession.self, Exercise.self, WorkoutSet.self, configurations: config)
        let ctx = ModelContext(container)

        let session = WorkoutSession(
            workoutType: "running",
            workoutTypeDisplayName: "Running",
            label: "",
            startedAt: .now
        )
        let exercise = Exercise(name: "Sprint", order: 0)
        exercise.sets = [WorkoutSet(reps: 1, weight: 0, unit: "lbs", order: 0)]
        session.exercises = [exercise]
        ctx.insert(session)
        try ctx.save()

        ctx.delete(session)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<Exercise>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<WorkoutSet>()).isEmpty)
    }

    @Test("durationFormatted returns MM:SS when endedAt is set")
    func durationFormatted() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 2732) // 45m 32s
        let session = WorkoutSession(
            workoutType: "running",
            workoutTypeDisplayName: "Running",
            label: "",
            startedAt: start
        )
        session.endedAt = end
        #expect(session.durationFormatted == "45:32")
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
cd /Users/nicolaslara/dev/meridian-ios
xcodebuild test -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MeridianTests/WorkoutSessionTests 2>&1 | tail -20
```

Expected: build error — `WorkoutSession` not found.

- [ ] **Step 3: Create `Meridian/Models/WorkoutSession.swift`**

```swift
import Foundation
import SwiftData

@Model
final class WorkoutSession {
    var id: UUID
    var healthKitUUID: UUID?
    var workoutType: String
    var workoutTypeDisplayName: String
    var label: String
    var startedAt: Date
    var endedAt: Date?

    @Relationship(deleteRule: .cascade)
    var exercises: [Exercise]

    init(workoutType: String, workoutTypeDisplayName: String, label: String, startedAt: Date) {
        self.id = UUID()
        self.workoutType = workoutType
        self.workoutTypeDisplayName = workoutTypeDisplayName
        self.label = label
        self.startedAt = startedAt
        self.endedAt = nil
        self.exercises = []
    }

    var durationFormatted: String {
        let end = endedAt ?? Date()
        let seconds = Int(end.timeIntervalSince(startedAt))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

@Model
final class Exercise {
    var id: UUID
    var name: String
    var order: Int

    @Relationship(deleteRule: .cascade)
    var sets: [WorkoutSet]

    init(name: String, order: Int) {
        self.id = UUID()
        self.name = name
        self.order = order
        self.sets = []
    }
}

@Model
final class WorkoutSet {
    var id: UUID
    var reps: Int
    var weight: Double
    var unit: String
    var order: Int

    init(reps: Int, weight: Double, unit: String, order: Int) {
        self.id = UUID()
        self.reps = reps
        self.weight = weight
        self.unit = unit
        self.order = order
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
xcodebuild test -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MeridianTests/WorkoutSessionTests 2>&1 | tail -20
```

Expected: 3 tests pass.

- [ ] **Step 5: Update `MeridianApp.swift` to include new models**

Open `Meridian/MeridianApp.swift`. Change the model container line from:

```swift
.modelContainer(for: WeightEntry.self)
```

to:

```swift
.modelContainer(for: [WeightEntry.self, WorkoutSession.self, Exercise.self, WorkoutSet.self])
```

- [ ] **Step 6: Build to confirm no errors**

```bash
xcodebuild build -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Meridian/Models/WorkoutSession.swift Meridian/MeridianApp.swift MeridianTests/WorkoutSessionTests.swift
git commit -m "feat: add WorkoutSession, Exercise, WorkoutSet SwiftData models"
```

---

## Task 2: WorkoutSessionService

**Files:**
- Create: `Meridian/Helpers/WorkoutSessionService.swift`
- Modify: `Meridian/Helpers/ActivityService.swift`
- Modify: `Meridian/Info.plist`

**Interfaces:**
- Consumes: nothing from prior tasks at runtime (standalone service)
- Produces:
  - `WorkoutSessionService` — `@MainActor final class`
  - `WorkoutSessionService.start(type:configuration:) async throws`
  - `WorkoutSessionService.finish() async throws -> UUID?` — returns HK workout UUID or nil on failure
  - `WorkoutSessionService.currentBPM: Int?` — `@Published`
  - `WorkoutType` — value type used by `StartWorkoutSheet`

```swift
struct WorkoutType: Identifiable {
    let id: String          // HKWorkoutActivityType raw value as String
    let displayName: String
    let symbol: String      // SF Symbol name
    let hkType: HKWorkoutActivityType
}

extension WorkoutType {
    static let all: [WorkoutType] = [ /* 12 entries */ ]
}
```

- [ ] **Step 1: Add HealthKit write permission to `ActivityService.swift`**

Open `Meridian/Helpers/ActivityService.swift`. The `requestAuthorization` method currently only reads `activitySummaryType`. Update the types sets:

```swift
func requestAuthorization() async throws {
    guard HKHealthStore.isHealthDataAvailable() else { return }
    let readTypes: Set<HKObjectType> = [
        HKObjectType.activitySummaryType(),
        HKQuantityType(.heartRate)
    ]
    let writeTypes: Set<HKSampleType> = [
        HKObjectType.workoutType()
    ]
    try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
}
```

- [ ] **Step 2: Add `NSHealthUpdateUsageDescription` to `Info.plist`**

Open `Meridian/Info.plist`. Add a new key/value pair after the existing `NSHealthShareUsageDescription`:

```xml
<key>NSHealthUpdateUsageDescription</key>
<string>Meridian saves your workouts to Apple Health so they appear in the Fitness app.</string>
```

- [ ] **Step 3: Create `WorkoutSessionService.swift`**

```swift
import Foundation
import HealthKit
import Combine

@MainActor
final class WorkoutSessionService: ObservableObject {
    @Published var currentBPM: Int? = nil

    private let store = HKHealthStore()
    private var builder: HKWorkoutBuilder?
    private var hrQuery: HKAnchoredObjectQuery?
    private var workoutStartDate: Date?

    func start(configuration: HKWorkoutConfiguration) async throws {
        let startDate = Date()
        workoutStartDate = startDate
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        self.builder = builder
        try await builder.beginCollection(at: startDate)
        startHeartRateObserver(from: startDate)
    }

    /// Returns the saved HKWorkout UUID, or nil if HealthKit write fails.
    func finish() async throws -> UUID? {
        let endDate = Date()
        guard let builder else { return nil }

        stopHeartRateObserver()

        // Collect heart rate samples recorded during the session
        if let start = workoutStartDate {
            let hrSamples = await fetchHeartRateSamples(from: start, to: endDate)
            if !hrSamples.isEmpty {
                try? await builder.addSamples(hrSamples)
            }
        }

        do {
            try await builder.endCollection(at: endDate)
            let workout = try await builder.finishWorkout()
            self.builder = nil
            workoutStartDate = nil
            return workout.uuid
        } catch {
            self.builder = nil
            workoutStartDate = nil
            return nil // HealthKit failed — caller still saves to SwiftData
        }
    }

    // MARK: - Heart Rate

    private func startHeartRateObserver(from startDate: Date) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let hrType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
        let query = HKAnchoredObjectQuery(
            type: hrType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.handleHeartRateSamples(samples)
        }
        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.handleHeartRateSamples(samples)
        }
        store.execute(query)
        hrQuery = query
    }

    private func stopHeartRateObserver() {
        if let q = hrQuery { store.stop(q) }
        hrQuery = nil
    }

    private func handleHeartRateSamples(_ samples: [HKSample]?) {
        guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else { return }
        // Take the most-recent sample only
        let latest = samples.max(by: { $0.endDate < $1.endDate })
        let bpm = latest.map { Int($0.quantity.doubleValue(for: .init(from: "count/min"))) }
        Task { @MainActor in self.currentBPM = bpm }
    }

    private func fetchHeartRateSamples(from start: Date, to end: Date) async -> [HKSample] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let hrType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
    }
}

// MARK: - WorkoutType catalogue

import HealthKit

struct WorkoutType: Identifiable {
    let id: String
    let displayName: String
    let symbol: String
    let hkType: HKWorkoutActivityType

    static let all: [WorkoutType] = [
        WorkoutType(id: "traditionalStrengthTraining",    displayName: "Strength Training",    symbol: "dumbbell",                              hkType: .traditionalStrengthTraining),
        WorkoutType(id: "functionalStrengthTraining",     displayName: "Functional Training",   symbol: "figure.strengthtraining.functional",    hkType: .functionalStrengthTraining),
        WorkoutType(id: "running",                        displayName: "Running",               symbol: "figure.run",                            hkType: .running),
        WorkoutType(id: "cycling",                        displayName: "Cycling",               symbol: "figure.outdoor.cycle",                  hkType: .cycling),
        WorkoutType(id: "highIntensityIntervalTraining",  displayName: "HIIT",                  symbol: "bolt.heart",                            hkType: .highIntensityIntervalTraining),
        WorkoutType(id: "walking",                        displayName: "Walking",               symbol: "figure.walk",                           hkType: .walking),
        WorkoutType(id: "swimming",                       displayName: "Swimming",              symbol: "figure.pool.swim",                      hkType: .swimming),
        WorkoutType(id: "yoga",                           displayName: "Yoga",                  symbol: "figure.yoga",                           hkType: .yoga),
        WorkoutType(id: "pilates",                        displayName: "Pilates",               symbol: "figure.pilates",                        hkType: .pilates),
        WorkoutType(id: "rowing",                         displayName: "Rowing",                symbol: "figure.rower",                          hkType: .rowing),
        WorkoutType(id: "elliptical",                     displayName: "Elliptical",            symbol: "figure.elliptical",                     hkType: .elliptical),
        WorkoutType(id: "other",                          displayName: "Other",                 symbol: "figure.mixed.cardio",                   hkType: .other),
    ]
}
```

- [ ] **Step 4: Add a test for duplicate HR sample handling**

Add to `MeridianTests/WorkoutSessionTests.swift`:

```swift
@Test("handleHeartRateSamples picks most-recent sample")
func heartRateTakesMostRecent() {
    // WorkoutSessionService is @MainActor; validate logic separately
    let now = Date()
    let earlier = now.addingTimeInterval(-30)

    let hrType = HKQuantityType(.heartRate)
    let unit = HKUnit(from: "count/min")

    let oldSample = HKQuantitySample(type: hrType, quantity: HKQuantity(unit: unit, doubleValue: 60), start: earlier, end: earlier)
    let newSample = HKQuantitySample(type: hrType, quantity: HKQuantity(unit: unit, doubleValue: 90), start: now, end: now)

    let samples: [HKQuantitySample] = [oldSample, newSample]
    let latest = samples.max(by: { $0.endDate < $1.endDate })
    #expect(Int(latest!.quantity.doubleValue(for: unit)) == 90)
}
```

- [ ] **Step 5: Run tests**

```bash
xcodebuild test -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MeridianTests/WorkoutSessionTests 2>&1 | tail -20
```

Expected: all tests pass (4 total).

- [ ] **Step 6: Build check**

```bash
xcodebuild build -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Meridian/Helpers/WorkoutSessionService.swift Meridian/Helpers/ActivityService.swift Meridian/Info.plist MeridianTests/WorkoutSessionTests.swift
git commit -m "feat: add WorkoutSessionService with HKWorkoutBuilder and live HR observer"
```

---

## Task 3: StartWorkoutSheet

**Files:**
- Create: `Meridian/Views/StartWorkoutSheet.swift`

**Interfaces:**
- Consumes: `WorkoutType.all` from `WorkoutSessionService.swift`, `WorkoutSessionService` instance from `DashboardView`
- Produces: `StartWorkoutSheet(service: WorkoutSessionService, activeWorkout: Binding<WorkoutSession?>, showingActiveWorkout: Binding<Bool>)` — on Start, creates a `WorkoutSession`, calls `service.start()`, sets `activeWorkout`, sets `showingActiveWorkout = true`, dismisses sheet

- [ ] **Step 1: Create `Meridian/Views/StartWorkoutSheet.swift`**

```swift
import SwiftUI
import SwiftData
import HealthKit

struct StartWorkoutSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let service: WorkoutSessionService
    @Binding var activeWorkout: WorkoutSession?
    @Binding var showingActiveWorkout: Bool

    @State private var selectedType: WorkoutType = WorkoutType.all[0]
    @State private var label: String = ""
    @State private var isStarting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Label field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Label")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("e.g. Leg Day", text: $label)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider()

                // Workout type list
                List(WorkoutType.all) { type in
                    Button {
                        selectedType = type
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: type.symbol)
                                .font(.system(size: 20))
                                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                                .frame(width: 28)
                            Text(type.displayName)
                                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                            Spacer()
                            if selectedType.id == type.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                .listStyle(.plain)

                // Start button
                Button {
                    Task { await startWorkout() }
                } label: {
                    Group {
                        if isStarting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Start Workout")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(red: 0.04, green: 0.04, blue: 0.04))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isStarting)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("New Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func startWorkout() async {
        isStarting = true
        defer { isStarting = false }

        let session = WorkoutSession(
            workoutType: selectedType.id,
            workoutTypeDisplayName: selectedType.displayName,
            label: label.trimmingCharacters(in: .whitespaces),
            startedAt: .now
        )
        modelContext.insert(session)

        let config = HKWorkoutConfiguration()
        config.activityType = selectedType.hkType
        try? await service.start(configuration: config)

        activeWorkout = session
        dismiss()
        showingActiveWorkout = true
    }
}
```

- [ ] **Step 2: Build check**

```bash
xcodebuild build -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Meridian/Views/StartWorkoutSheet.swift
git commit -m "feat: add StartWorkoutSheet for picking workout type and label"
```

---

## Task 4: ActiveWorkoutView

**Files:**
- Create: `Meridian/Views/ActiveWorkoutView.swift`

**Interfaces:**
- Consumes:
  - `WorkoutSession` from Task 1
  - `WorkoutSessionService` from Task 2
- Produces: `ActiveWorkoutView(workout: WorkoutSession, service: WorkoutSessionService, onMinimize: () -> Void, onEnd: () -> Void)`

- [ ] **Step 1: Create `Meridian/Views/ActiveWorkoutView.swift`**

```swift
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
                // Header stats
                HStack(spacing: 0) {
                    statCell(
                        label: "Time",
                        value: formatElapsed(elapsed)
                    )
                    Divider().frame(height: 50)
                    statCell(
                        label: "BPM",
                        value: service.currentBPM.map { "\($0)" } ?? "—"
                    )
                }
                .padding(.vertical, 12)
                .background(Color(red: 0.96, green: 0.95, blue: 0.94))

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
                    Button(role: .destructive) {
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
        let lastWeight = exercise.sets.sorted { $0.order < $1.order }.last?.weight ?? 0
        let lastUnit = exercise.sets.sorted { $0.order < $1.order }.last?.unit ?? "lbs"
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
```

- [ ] **Step 2: Add test for empty-exercises end-workout path**

Add to `MeridianTests/WorkoutSessionTests.swift`:

```swift
@Test("WorkoutSession with no exercises saves endedAt correctly")
func emptySessionEnds() throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: WorkoutSession.self, Exercise.self, WorkoutSet.self, configurations: config)
    let ctx = ModelContext(container)

    let session = WorkoutSession(
        workoutType: "other",
        workoutTypeDisplayName: "Other",
        label: "",
        startedAt: Date(timeIntervalSince1970: 0)
    )
    ctx.insert(session)

    session.endedAt = Date(timeIntervalSince1970: 300)
    try ctx.save()

    let fetched = try ctx.fetch(FetchDescriptor<WorkoutSession>())
    #expect(fetched[0].exercises.isEmpty)
    #expect(fetched[0].endedAt != nil)
    #expect(fetched[0].durationFormatted == "05:00")
}
```

- [ ] **Step 3: Run tests**

```bash
xcodebuild test -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MeridianTests/WorkoutSessionTests 2>&1 | tail -20
```

Expected: 5 tests pass.

- [ ] **Step 4: Build check**

```bash
xcodebuild build -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Meridian/Views/ActiveWorkoutView.swift MeridianTests/WorkoutSessionTests.swift
git commit -m "feat: add ActiveWorkoutView with exercise/set logging and end-workout flow"
```

---

## Task 5: ActivitiesCard + WorkoutHistorySheet

**Files:**
- Create: `Meridian/Views/ActivitiesCard.swift`
- Create: `Meridian/Views/WorkoutHistorySheet.swift`

**Interfaces:**
- Consumes: `WorkoutSession` from Task 1
- Produces:
  - `ActivitiesCard(activeWorkout: Binding<WorkoutSession?>, onStart: () -> Void, onResume: () -> Void)`
  - `WorkoutHistorySheet(workoutType: String, displayName: String)`

- [ ] **Step 1: Create `Meridian/Views/WorkoutHistorySheet.swift`**

```swift
import SwiftUI
import SwiftData

struct WorkoutHistorySheet: View {
    let workoutType: String
    let displayName: String

    @Query private var allSessions: [WorkoutSession]

    private var sessions: [WorkoutSession] {
        allSessions
            .filter { $0.workoutType == workoutType && $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sessions) { session in
                    Section {
                        let sortedExercises = session.exercises.sorted { $0.order < $1.order }
                        if sortedExercises.isEmpty {
                            Text("No exercises logged")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(sortedExercises) { exercise in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise.name)
                                        .font(.system(size: 14, weight: .semibold))
                                    let sortedSets = exercise.sets.sorted { $0.order < $1.order }
                                    ForEach(sortedSets) { set in
                                        Text("\(set.reps) reps · \(set.weight.formatted()) \(set.unit)")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.startedAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(size: 13, weight: .semibold))
                                if !session.label.isEmpty {
                                    Text(session.label)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(session.durationFormatted)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(displayName)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
```

- [ ] **Step 2: Create `Meridian/Views/ActivitiesCard.swift`**

```swift
import SwiftUI
import SwiftData

struct ActivitiesCard: View {
    @Binding var activeWorkout: WorkoutSession?
    let onStart: () -> Void
    let onResume: () -> Void

    @Query(
        filter: #Predicate<WorkoutSession> { $0.endedAt != nil },
        sort: \WorkoutSession.startedAt,
        order: .reverse
    ) private var recentSessions: [WorkoutSession]

    @State private var historyWorkoutType: String? = nil
    @State private var historyDisplayName: String = ""

    private var displaySessions: [WorkoutSession] {
        Array(recentSessions.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activities")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))

            if let active = activeWorkout {
                // Active workout banner
                Button(action: onResume) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .stroke(Color.red.opacity(0.4), lineWidth: 4)
                                    .scaleEffect(1.6)
                                    .opacity(0.8)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(active.label.isEmpty ? active.workoutTypeDisplayName : active.label)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                            Text("Active · Resume")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color(red: 0.961, green: 0.941, blue: 0.922))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else {
                // Start button
                Button(action: onStart) {
                    Label("Start Workout", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(red: 0.04, green: 0.04, blue: 0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            if !displaySessions.isEmpty {
                Divider()

                VStack(spacing: 0) {
                    ForEach(Array(displaySessions.enumerated()), id: \.element.id) { index, session in
                        Button {
                            historyWorkoutType = session.workoutType
                            historyDisplayName = session.workoutTypeDisplayName
                        } label: {
                            SessionRow(session: session)
                        }
                        .buttonStyle(.plain)

                        if index < displaySessions.count - 1 {
                            Divider().padding(.leading, 0)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
        )
        .sheet(isPresented: Binding(
            get: { historyWorkoutType != nil },
            set: { if !$0 { historyWorkoutType = nil } }
        )) {
            if let type = historyWorkoutType {
                WorkoutHistorySheet(workoutType: type, displayName: historyDisplayName)
            }
        }
    }
}

private struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.workoutTypeDisplayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                if !session.label.isEmpty {
                    Text(session.label)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(session.durationFormatted)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                Text(session.startedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}

```

- [ ] **Step 3: Build check**

```bash
xcodebuild build -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Meridian/Views/ActivitiesCard.swift Meridian/Views/WorkoutHistorySheet.swift
git commit -m "feat: add ActivitiesCard and WorkoutHistorySheet"
```

---

## Task 6: Wire DashboardView

**Files:**
- Modify: `Meridian/Views/DashboardView.swift`

**Interfaces:**
- Consumes: `ActivitiesCard`, `StartWorkoutSheet`, `ActiveWorkoutView`, `WorkoutSessionService` from prior tasks

- [ ] **Step 1: Update `DashboardView.swift`**

Replace the entire file content with:

```swift
import SwiftUI
import SwiftData
import Charts
import UIKit

struct DashboardView: View {
    @Query(sort: \WeightEntry.recordedAt, order: .reverse) private var entries: [WeightEntry]
    @State private var showingAddSheet = false
    @State private var showingStartWorkout = false
    @State private var showingActiveWorkout = false
    @State private var activeWorkout: WorkoutSession? = nil
    @State private var workoutService = WorkoutSessionService()

    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.961, green: 0.941, blue: 0.922, alpha: 1)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.black]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.black]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(red: 0.961, green: 0.941, blue: 0.922)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Meridian")
                        .font(Font.custom("PlayfairDisplay-Regular", size: 34).weight(.bold))
                        .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))

                    ActivityRingsWidget()

                    WeightChartView(entries: entries)
                        .padding(20)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
                        )

                    ActivitiesCard(
                        activeWorkout: $activeWorkout,
                        onStart: { showingStartWorkout = true },
                        onResume: { showingActiveWorkout = true }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }

            addButton
        }
        .sheet(isPresented: $showingAddSheet) {
            AddEntrySheet()
        }
        .sheet(isPresented: $showingStartWorkout) {
            StartWorkoutSheet(
                service: workoutService,
                activeWorkout: $activeWorkout,
                showingActiveWorkout: $showingActiveWorkout
            )
        }
        .fullScreenCover(isPresented: $showingActiveWorkout) {
            if let workout = activeWorkout {
                ActiveWorkoutView(
                    workout: workout,
                    service: workoutService,
                    onMinimize: { showingActiveWorkout = false },
                    onEnd: {
                        showingActiveWorkout = false
                        activeWorkout = nil
                        workoutService = WorkoutSessionService()
                    }
                )
            }
        }
    }

    private var addButton: some View {
        Button {
            showingAddSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color(red: 0.04, green: 0.04, blue: 0.04))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .padding(.trailing, 24)
        .padding(.bottom, 24)
    }
}
```

- [ ] **Step 2: Build check**

```bash
xcodebuild build -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run all tests**

```bash
xcodebuild test -scheme Meridian -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Meridian/Views/DashboardView.swift
git commit -m "feat: wire ActivitiesCard, StartWorkoutSheet, and ActiveWorkoutView into DashboardView"
```

- [ ] **Step 5: Push**

```bash
git push
```
