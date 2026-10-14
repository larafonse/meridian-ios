# Activities Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Log tab with a full-history Activities tab and make weight log entries accessible by tapping the weight chart on Dashboard.

**Architecture:** Three focused changes in sequence: (1) extract WeightLogSheet from LogView, (2) wire it into Dashboard, (3) build ActivitiesView and swap it into ContentView replacing LogView. `WorkoutListItem.merge()` and all existing sheet views are reused without modification.

**Tech Stack:** SwiftUI, SwiftData (@Query, @Environment(\.modelContext)), HealthKit (HKWorkout, HealthKitWorkoutService)

**Spec:** `docs/superpowers/specs/2026-10-13-activities-tab-design.md`

## Global Constraints

- SwiftUI only — no UIKit view hierarchy changes
- Beige background: `Color(red: 0.961, green: 0.941, blue: 0.922)`
- Dark foreground: `Color(red: 0.04, green: 0.04, blue: 0.04)`
- Card border: `Color(red: 0.898, green: 0.898, blue: 0.898)`
- Sheet navigation title display mode: `.inline` for sheets, `.large` for full tabs
- All SwiftData deletes followed by `try? modelContext.save()`
- No Start Workout button in ActivitiesView

## Review Focus

- Empty state in ActivitiesView when both HK workouts and local sessions are empty — list should show a message, not a blank screen
- Weight chart tap target is visually subtle — nothing signals it's tappable; may need a cursor/visual affordance
- ActivitiesView loads HK workouts on `.task` — list appears empty briefly before data arrives; should show a loading or empty placeholder during fetch
- Swipe-to-delete in ActivitiesView only available when a local session exists (`item.session != nil`), consistent with ActivitiesCard — verify HK-only rows correctly omit the action
- WeightLogSheet swipe-to-delete uses index offsets from `entries` — must verify the @Query sort order matches the displayed order so deletes remove the correct row

---

### Task 1: Create WeightLogSheet

**Files:**
- Create: `Meridian/Views/WeightLogSheet.swift`

**Interfaces:**
- Produces: `WeightLogSheet` — a SwiftUI `View` with no init parameters, presented as a sheet

- [ ] **Step 1: Create WeightLogSheet.swift**

Note: `EntryRow` is currently defined in `LogView.swift`. We include it here too so that when `LogView.swift` is deleted in Task 4, `WeightLogSheet.swift` is self-contained.

```swift
import SwiftUI
import SwiftData

struct WeightLogSheet: View {
    @Query(sort: \WeightEntry.recordedAt, order: .reverse) private var entries: [WeightEntry]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.961, green: 0.941, blue: 0.922)
                    .ignoresSafeArea()

                if entries.isEmpty {
                    Text("No entries yet.\nLog your first weight from the Dashboard.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    List {
                        ForEach(entries) { entry in
                            EntryRow(entry: entry)
                                .listRowBackground(Color.white)
                                .listRowSeparatorTint(Color(red: 0.898, green: 0.898, blue: 0.898))
                        }
                        .onDelete(perform: deleteEntries)
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Weight Log")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(entries[index])
        }
        try? modelContext.save()
    }
}

private struct EntryRow: View {
    let entry: WeightEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.recordedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))
            }
            Spacer()
            Text("\(formatted(entry.weight)) \(entry.unit)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
        }
        .padding(.vertical, 4)
    }

    private func formatted(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
```

- [ ] **Step 2: Build to verify no compile errors**

In Xcode: Product → Build (⌘B). Expected: build succeeds. `EntryRow` is defined in `LogView.swift` — it will still compile since that file exists at this point.

- [ ] **Step 3: Commit**

```bash
git add Meridian/Views/WeightLogSheet.swift
git commit -m "feat: add WeightLogSheet extracted from LogView"
```

---

### Task 2: Wire WeightLogSheet into DashboardView

**Files:**
- Modify: `Meridian/Views/DashboardView.swift`

**Interfaces:**
- Consumes: `WeightLogSheet` (no-arg init from Task 1)

- [ ] **Step 1: Add showingWeightLog state and tap gesture**

In `DashboardView`, add one new `@State` property after the existing state vars:

```swift
@State private var showingWeightLog = false
```

- [ ] **Step 2: Wrap WeightChartView with a Button**

Replace the current WeightChartView block (lines 53–63 in DashboardView.swift):

```swift
HStack {
    WeightChartView(entries: entries)
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
        )
        .frame(maxWidth: UIScreen.main.bounds.width / 2)
    Spacer()
}
```

with:

```swift
HStack {
    Button { showingWeightLog = true } label: {
        WeightChartView(entries: entries)
            .padding(12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
            )
            .frame(maxWidth: UIScreen.main.bounds.width / 2)
    }
    .buttonStyle(.plain)
    Spacer()
}
```

- [ ] **Step 3: Present WeightLogSheet**

Add a `.sheet` modifier after the existing `.sheet(isPresented: $showingAddSheet)` block:

```swift
.sheet(isPresented: $showingWeightLog) {
    WeightLogSheet()
}
```

- [ ] **Step 4: Build to verify**

Product → Build (⌘B). Expected: build succeeds with no errors or warnings.

- [ ] **Step 5: Commit**

```bash
git add Meridian/Views/DashboardView.swift
git commit -m "feat: open WeightLogSheet when tapping weight chart"
```

---

### Task 3: Create ActivitiesView

**Files:**
- Modify: `Meridian/Helpers/HealthKitWorkoutService.swift` — add `fetchAllWorkouts()`
- Modify: `Meridian/Views/ActivitiesCard.swift` — make `WorkoutItemRow` internal
- Create: `Meridian/Views/ActivitiesView.swift`

**Interfaces:**
- Consumes: `WorkoutListItem.merge(sessions:hkWorkouts:)` (defined in `ActivitiesCard.swift`)
- Consumes: `WorkoutItemRow` (defined in `ActivitiesCard.swift`, made internal in this task)
- Consumes: `WorkoutLogSheet(session:hkWorkout:)` (existing sheet)
- Consumes: `TemplateListSheet()` (existing sheet)
- Consumes: `HealthKitWorkoutService.fetchAllWorkouts()` (added in this task)
- Produces: `ActivitiesView` — a SwiftUI `View` with no init parameters, used as a tab

- [ ] **Step 1: Add fetchAllWorkouts() to HealthKitWorkoutService**

In `Meridian/Helpers/HealthKitWorkoutService.swift`, add after `fetchRecentWorkouts`:

```swift
func fetchAllWorkouts() async throws -> [HKWorkout] {
    guard HKHealthStore.isHealthDataAvailable() else { return [] }
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
    return try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: nil,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samples, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
        }
        store.execute(query)
    }
}
```

- [ ] **Step 2: Make WorkoutItemRow internal**

In `Meridian/Views/ActivitiesCard.swift`, change line 211:

```swift
// Before:
private struct WorkoutItemRow: View {

// After:
struct WorkoutItemRow: View {
```

- [ ] **Step 3: Create ActivitiesView.swift**

```swift
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
```

- [ ] **Step 4: Build to verify**

Product → Build (⌘B). Expected: build succeeds with no errors.

- [ ] **Step 5: Commit**

```bash
git add Meridian/Helpers/HealthKitWorkoutService.swift \
        Meridian/Views/ActivitiesCard.swift \
        Meridian/Views/ActivitiesView.swift
git commit -m "feat: add ActivitiesView with full workout history and Templates access"
```

---

### Task 4: Swap tab and delete LogView

**Files:**
- Modify: `Meridian/Views/ContentView.swift`
- Delete: `Meridian/Views/LogView.swift`

**Interfaces:**
- Consumes: `ActivitiesView` (no-arg init from Task 3)

- [ ] **Step 1: Replace Log tab with Activities tab in ContentView**

Replace the LogView tab item block:

```swift
// Before:
LogView()
    .tabItem {
        Label("Log", systemImage: "list.bullet")
    }

// After:
ActivitiesView()
    .tabItem {
        Label("Activities", systemImage: "figure.run")
    }
```

- [ ] **Step 2: Build to verify**

Product → Build (⌘B). Expected: build succeeds. `LogView` is still present at this point — we delete it next only after confirming the build is clean.

- [ ] **Step 3: Delete LogView.swift**

In Xcode's Project Navigator, right-click `LogView.swift` → Delete → Move to Trash.

Or via terminal:
```bash
rm Meridian/Views/LogView.swift
```

Then in Xcode, if the file still shows in the project navigator with a red missing-file indicator, select it and press Delete to remove the reference.

- [ ] **Step 4: Build again to confirm clean**

Product → Build (⌘B). Expected: build succeeds with no missing-file errors. `EntryRow` was moved into `WeightLogSheet.swift` in Task 1 so no dangling references remain.

- [ ] **Step 5: Commit**

```bash
git add Meridian/Views/ContentView.swift
git rm Meridian/Views/LogView.swift
git commit -m "feat: replace Log tab with Activities tab, remove LogView"
```
