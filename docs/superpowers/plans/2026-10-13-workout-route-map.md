# Workout Route Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display an Apple Watch GPS route on a MapKit map, accessible via a button in WorkoutHistorySheet for cycling, running, and walking sessions.

**Architecture:** A new `WorkoutRouteService` queries HealthKit for the `HKWorkoutRoute` tied to a workout UUID and returns `[CLLocationCoordinate2D]`. A new `WorkoutRouteMapView` renders those coordinates as a `MapPolyline` in three states (loading / empty / map). `WorkoutHistorySheet` grows a map icon button on GPS-capable workout rows that have a HealthKit UUID.

**Tech Stack:** SwiftUI, MapKit (`Map`, `MapPolyline`, `Annotation`), HealthKit (`HKWorkoutRouteQuery`, `HKAnchoredObjectQuery`, `HKSeriesType.workoutRoute()`)

**Spec:** `docs/superpowers/specs/2026-10-13-workout-route-map-design.md`

## Global Constraints

- iOS 17.0+ deployment target — use iOS 17 `Map(initialPosition:)` API, not deprecated `Map(coordinateRegion:)`
- Swift 6.0 — all new types must be `@unchecked Sendable` or concurrency-safe
- No third-party dependencies
- GPS-capable `workoutType` strings: `"cycling"`, `"running"`, `"walking"`
- Map button only shown when `session.healthKitUUID != nil` AND `workoutType` is GPS-capable
- Map style: `.standard`; polyline color: `.accentColor`; line width: 3
- Stats bar shows distance in km (one decimal) and duration as `m:ss` or `h:mm:ss`
- Minimum map span: 0.005 degrees on both axes (prevents zero-span crash on single-point routes)

## Review Focus

1. **`session.healthKitUUID == nil`** — button must not appear; guard on `healthKitUUID` in the history row.
2. **Route query returns zero coordinates** (GPS off, indoor ride) — view must show "No Route Data" `ContentUnavailableView`, not a blank map; tested in Task 2.
3. **`HKWorkoutRouteQuery` delivers `done = true` on first batch** — locations must be appended before the continuation resumes; the accumulation order in `fetchCoordinates` pins this.
4. **Single-coordinate route** — `routeMapRegion(for:)` must clamp to minimum span; tested in Task 3.
5. **HealthKit auth not yet granted** — `fetchWorkout` and `fetchRoute` return empty arrays; view shows empty state without crashing; tested in Task 3.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Meridian/Helpers/ActivityService.swift` | Modify | Add `HKSeriesType.workoutRoute()` to read permissions |
| `Meridian/Helpers/WorkoutRouteService.swift` | Create | Fetch `HKWorkout` by UUID; fetch `[CLLocationCoordinate2D]` from its route |
| `Meridian/Views/WorkoutRouteMapView.swift` | Create | Map sheet with loading / empty / map states and stats bar |
| `Meridian/Views/WorkoutHistorySheet.swift` | Modify | Add map icon button on GPS workout rows |
| `MeridianTests/WorkoutRouteMapViewTests.swift` | Create | Tests for `routeMapRegion(for:)` and `formatRouteDuration(_:)` |

---

### Task 1: Add HealthKit Route Read Permission

**Files:**
- Modify: `Meridian/Helpers/ActivityService.swift:8-12`

**Interfaces:**
- Produces: `HKSeriesType.workoutRoute()` included in the app's HealthKit read grant — required by all subsequent route queries.

- [ ] **Step 1: Add the route type to the read set**

  Open `Meridian/Helpers/ActivityService.swift`. Find the `readTypes` set in `requestAuthorization()` and add `HKSeriesType.workoutRoute()`:

  ```swift
  let readTypes: Set<HKObjectType> = [
      HKObjectType.activitySummaryType(),
      HKQuantityType(.heartRate),
      HKObjectType.workoutType(),
      HKSeriesType.workoutRoute()
  ]
  ```

- [ ] **Step 2: Build and confirm no errors**

  Build the Meridian target (`⌘B`). No new errors or warnings expected — `HKSeriesType` is part of HealthKit which is already imported.

- [ ] **Step 3: Commit**

  ```bash
  git add Meridian/Helpers/ActivityService.swift
  git commit -m "feat: request HealthKit route read permission"
  ```

---

### Task 2: WorkoutRouteService

**Files:**
- Create: `Meridian/Helpers/WorkoutRouteService.swift`

**Interfaces:**
- Produces:
  - `WorkoutRouteService.fetchWorkout(uuid: UUID) async -> HKWorkout?`
  - `WorkoutRouteService.fetchRoute(for: HKWorkout) async -> [CLLocationCoordinate2D]`

- [ ] **Step 1: Create the file with the full implementation**

  Create `Meridian/Helpers/WorkoutRouteService.swift`:

  ```swift
  import HealthKit
  import CoreLocation

  final class WorkoutRouteService: @unchecked Sendable {
      private let store = HKHealthStore()

      /// Looks up an HKWorkout in HealthKit by UUID. Returns nil when unavailable or not found.
      func fetchWorkout(uuid: UUID) async -> HKWorkout? {
          guard HKHealthStore.isHealthDataAvailable() else { return nil }
          let predicate = HKQuery.predicateForObject(with: uuid)
          return await withCheckedContinuation { continuation in
              let query = HKSampleQuery(
                  sampleType: HKObjectType.workoutType(),
                  predicate: predicate,
                  limit: 1,
                  sortDescriptors: nil
              ) { _, samples, _ in
                  continuation.resume(returning: samples?.first as? HKWorkout)
              }
              store.execute(query)
          }
      }

      /// Returns all GPS coordinates from the HKWorkoutRoute associated with the given workout.
      /// Returns an empty array when no route exists or HealthKit is unavailable.
      func fetchRoute(for workout: HKWorkout) async -> [CLLocationCoordinate2D] {
          guard HKHealthStore.isHealthDataAvailable() else { return [] }
          let routes = await fetchRoutes(for: workout)
          guard let route = routes.first else { return [] }
          return await fetchCoordinates(from: route)
      }

      private func fetchRoutes(for workout: HKWorkout) async -> [HKWorkoutRoute] {
          let predicate = HKQuery.predicateForObjects(from: workout)
          return await withCheckedContinuation { continuation in
              let query = HKAnchoredObjectQuery(
                  type: HKSeriesType.workoutRoute(),
                  predicate: predicate,
                  anchor: nil,
                  limit: HKObjectQueryNoLimit
              ) { _, samples, _, _, _ in
                  continuation.resume(returning: samples as? [HKWorkoutRoute] ?? [])
              }
              store.execute(query)
          }
      }

      private func fetchCoordinates(from route: HKWorkoutRoute) async -> [CLLocationCoordinate2D] {
          var coordinates: [CLLocationCoordinate2D] = []
          return await withCheckedContinuation { continuation in
              let query = HKWorkoutRouteQuery(route: route) { _, locations, done, _ in
                  if let locations {
                      coordinates.append(contentsOf: locations.map(\.coordinate))
                  }
                  if done {
                      continuation.resume(returning: coordinates)
                  }
              }
              store.execute(query)
          }
      }
  }
  ```

- [ ] **Step 2: Build and confirm no errors**

  Build the Meridian target (`⌘B`).

- [ ] **Step 3: Commit**

  ```bash
  git add Meridian/Helpers/WorkoutRouteService.swift
  git commit -m "feat: add WorkoutRouteService for HealthKit GPS route fetching"
  ```

---

### Task 3: WorkoutRouteMapView

**Files:**
- Create: `Meridian/Views/WorkoutRouteMapView.swift`
- Create: `MeridianTests/WorkoutRouteMapViewTests.swift`

**Interfaces:**
- Consumes:
  - `WorkoutRouteService.fetchWorkout(uuid: UUID) async -> HKWorkout?`
  - `WorkoutRouteService.fetchRoute(for: HKWorkout) async -> [CLLocationCoordinate2D]`
- Produces:
  - `WorkoutRouteMapView(workoutUUID: UUID)` — a sheet-presentable SwiftUI view
  - `routeMapRegion(for: [CLLocationCoordinate2D]) -> MKCoordinateRegion` — internal free function, testable
  - `formatRouteDuration(_ seconds: TimeInterval) -> String` — internal free function, testable

- [ ] **Step 1: Write the failing tests**

  Create `MeridianTests/WorkoutRouteMapViewTests.swift`:

  ```swift
  import XCTest
  import MapKit
  import CoreLocation
  @testable import Meridian

  final class WorkoutRouteMapViewTests: XCTestCase {

      // MARK: - routeMapRegion

      func test_mapRegion_centerIsMiddleOfBoundingBox() {
          let coords = [
              CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
              CLLocationCoordinate2D(latitude: 38.0, longitude: -121.0)
          ]
          let region = routeMapRegion(for: coords)
          XCTAssertEqual(region.center.latitude, 37.5, accuracy: 0.001)
          XCTAssertEqual(region.center.longitude, -121.5, accuracy: 0.001)
      }

      func test_mapRegion_spanHas30PercentPadding() {
          let coords = [
              CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
              CLLocationCoordinate2D(latitude: 38.0, longitude: -121.0)
          ]
          let region = routeMapRegion(for: coords)
          // raw delta 1.0 * 1.3 = 1.3
          XCTAssertEqual(region.span.latitudeDelta, 1.3, accuracy: 0.001)
          XCTAssertEqual(region.span.longitudeDelta, 1.3, accuracy: 0.001)
      }

      func test_mapRegion_singleCoordinate_usesMinimumSpan() {
          let coords = [CLLocationCoordinate2D(latitude: 37.5, longitude: -122.0)]
          let region = routeMapRegion(for: coords)
          XCTAssertEqual(region.center.latitude, 37.5, accuracy: 0.001)
          XCTAssertEqual(region.center.longitude, -122.0, accuracy: 0.001)
          XCTAssertGreaterThanOrEqual(region.span.latitudeDelta, 0.005)
          XCTAssertGreaterThanOrEqual(region.span.longitudeDelta, 0.005)
      }

      func test_mapRegion_emptyCoordinates_returnsDefaultRegion() {
          // Must not crash and must return a non-zero span
          let region = routeMapRegion(for: [])
          XCTAssertGreaterThan(region.span.latitudeDelta, 0)
          XCTAssertGreaterThan(region.span.longitudeDelta, 0)
      }

      // MARK: - formatRouteDuration

      func test_formatDuration_underOneHour_showsMinutesAndSeconds() {
          XCTAssertEqual(formatRouteDuration(0), "0:00")
          XCTAssertEqual(formatRouteDuration(65), "1:05")
          XCTAssertEqual(formatRouteDuration(3599), "59:59")
      }

      func test_formatDuration_oneHourOrMore_showsHoursMinutesSeconds() {
          XCTAssertEqual(formatRouteDuration(3600), "1:00:00")
          XCTAssertEqual(formatRouteDuration(3661), "1:01:01")
          XCTAssertEqual(formatRouteDuration(7322), "2:02:02")
      }
  }
  ```

- [ ] **Step 2: Run tests to verify they fail**

  In Xcode, run `MeridianTests` (`⌘U`). Tests fail with "use of unresolved identifier 'routeMapRegion'" and "use of unresolved identifier 'formatRouteDuration'". That is expected.

- [ ] **Step 3: Create WorkoutRouteMapView.swift**

  Create `Meridian/Views/WorkoutRouteMapView.swift`:

  ```swift
  import SwiftUI
  import MapKit
  import HealthKit
  import CoreLocation

  // MARK: - Pure helpers (internal for testability)

  func routeMapRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
      guard !coordinates.isEmpty else {
          return MKCoordinateRegion(
              center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
              span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
          )
      }
      let lats = coordinates.map(\.latitude)
      let lons = coordinates.map(\.longitude)
      let minLat = lats.min()!
      let maxLat = lats.max()!
      let minLon = lons.min()!
      let maxLon = lons.max()!
      let center = CLLocationCoordinate2D(
          latitude: (minLat + maxLat) / 2,
          longitude: (minLon + maxLon) / 2
      )
      let latDelta = max((maxLat - minLat) * 1.3, 0.005)
      let lonDelta = max((maxLon - minLon) * 1.3, 0.005)
      return MKCoordinateRegion(
          center: center,
          span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
      )
  }

  func formatRouteDuration(_ seconds: TimeInterval) -> String {
      let total = Int(seconds)
      let h = total / 3600
      let m = (total % 3600) / 60
      let s = total % 60
      if h > 0 {
          return String(format: "%d:%02d:%02d", h, m, s)
      } else {
          return String(format: "%d:%02d", m, s)
      }
  }

  // MARK: - View

  struct WorkoutRouteMapView: View {
      let workoutUUID: UUID

      @Environment(\.dismiss) private var dismiss
      @State private var coordinates: [CLLocationCoordinate2D] = []
      @State private var workout: HKWorkout?
      @State private var isLoading = true

      private let routeService = WorkoutRouteService()

      var body: some View {
          NavigationStack {
              content
                  .navigationTitle("Route")
                  .navigationBarTitleDisplayMode(.inline)
                  .toolbar {
                      ToolbarItem(placement: .topBarTrailing) {
                          Button("Done") { dismiss() }
                      }
                  }
          }
          .task { await loadRoute() }
      }

      @ViewBuilder
      private var content: some View {
          if isLoading {
              ProgressView("Loading route…")
                  .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else if coordinates.isEmpty {
              ContentUnavailableView(
                  "No Route Data",
                  systemImage: "map",
                  description: Text("No GPS route was recorded for this workout.")
              )
          } else {
              ZStack(alignment: .bottom) {
                  Map(initialPosition: .region(routeMapRegion(for: coordinates))) {
                      MapPolyline(coordinates: coordinates)
                          .stroke(Color.accentColor, lineWidth: 3)
                      if let first = coordinates.first {
                          Annotation("Start", coordinate: first, anchor: .center) {
                              Circle()
                                  .fill(.green)
                                  .frame(width: 12, height: 12)
                          }
                      }
                      if coordinates.count > 1, let last = coordinates.last {
                          Annotation("End", coordinate: last, anchor: .center) {
                              Circle()
                                  .fill(.red)
                                  .frame(width: 12, height: 12)
                          }
                      }
                  }
                  statsBar
              }
          }
      }

      private var statsBar: some View {
          HStack(spacing: 24) {
              if let distance = workout?.totalDistance {
                  let km = distance.doubleValue(for: .meterUnit(with: .kilo))
                  Label(String(format: "%.1f km", km), systemImage: "arrow.left.and.right")
              }
              if let workout {
                  Label(formatRouteDuration(workout.duration), systemImage: "clock")
              }
          }
          .font(.system(size: 14, weight: .medium))
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
          .frame(maxWidth: .infinity)
          .background(.ultraThinMaterial)
      }

      private func loadRoute() async {
          defer { isLoading = false }
          let hkWorkout = await routeService.fetchWorkout(uuid: workoutUUID)
          workout = hkWorkout
          guard let hkWorkout else { return }
          coordinates = await routeService.fetchRoute(for: hkWorkout)
      }
  }
  ```

- [ ] **Step 4: Run tests to verify they pass**

  In Xcode, run `MeridianTests` (`⌘U`). All 6 tests in `WorkoutRouteMapViewTests` must pass.

- [ ] **Step 5: Commit**

  ```bash
  git add Meridian/Views/WorkoutRouteMapView.swift MeridianTests/WorkoutRouteMapViewTests.swift
  git commit -m "feat: add WorkoutRouteMapView with map, loading, and empty states"
  ```

---

### Task 4: WorkoutHistorySheet — Map Button

**Files:**
- Modify: `Meridian/Views/WorkoutHistorySheet.swift`

**Interfaces:**
- Consumes: `WorkoutRouteMapView(workoutUUID: UUID)` from Task 3
- Consumes: `WorkoutSession.workoutType: String` and `WorkoutSession.healthKitUUID: UUID?`

- [ ] **Step 1: Add state and the GPS type set**

  Open `WorkoutHistorySheet.swift`. After the existing `@Query` property, add:

  ```swift
  @State private var routeWorkoutUUID: UUID?

  private let gpsWorkoutTypes: Set<String> = ["cycling", "running", "walking"]
  ```

- [ ] **Step 2: Add the map button to the section header**

  In the `header` closure of the `ForEach`, replace the existing `HStack` with:

  ```swift
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
          if gpsWorkoutTypes.contains(session.workoutType),
             let uuid = session.healthKitUUID {
              Button {
                  routeWorkoutUUID = uuid
              } label: {
                  Image(systemName: "map")
                      .font(.system(size: 14))
                      .foregroundStyle(.secondary)
              }
              .buttonStyle(.plain)
          }
          Text(session.durationFormatted)
              .font(.system(size: 12, design: .monospaced))
              .foregroundStyle(.secondary)
      }
  }
  ```

- [ ] **Step 3: Attach the sheet**

  After `.listStyle(.insetGrouped)`, add:

  ```swift
  .sheet(item: $routeWorkoutUUID) { uuid in
      WorkoutRouteMapView(workoutUUID: uuid)
  }
  ```

  `UUID` conforms to `Identifiable` (via `Foundation` on iOS 15.4+, well within iOS 17 target), so `item:` binding works directly.

- [ ] **Step 4: Build and manually verify**

  Build (`⌘B`). Open the app in Simulator or on device:
  1. Navigate to a cycling, running, or walking workout in history — a map icon appears in the section header.
  2. Tap it — the route sheet opens (shows loading spinner, then route or "No Route Data").
  3. Strength Training or other non-GPS workouts — no map icon appears.
  4. Dismiss the sheet — works with swipe-down or the Done button.

- [ ] **Step 5: Commit**

  ```bash
  git add Meridian/Views/WorkoutHistorySheet.swift
  git commit -m "feat: add route map button to GPS workout history rows"
  ```
