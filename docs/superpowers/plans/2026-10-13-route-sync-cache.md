# Route Sync & Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 50-workout in-memory fetch with a persistent binary file cache and incremental HealthKit sync so the Routes map loads instantly from disk and picks up new rides automatically.

**Architecture:** `RouteCache` persists coordinate data as binary `.dat` files keyed by workout UUID. `RouteSyncService` (`@Observable @MainActor`) loads all cached routes immediately, then concurrently fetches and caches only new HealthKit workouts. `RoutesView` observes `RouteSyncService` and shows a sync-progress pill while new routes arrive.

**Tech Stack:** Swift 6, SwiftUI `@Observable`, `TaskGroup`, `FileManager`, `CoreLocation`, `HealthKit`

**Spec:** `docs/superpowers/specs/2026-10-13-route-sync-cache-design.md`

## Global Constraints

- iOS 17.0+ — use `@Observable` (not `ObservableObject`)
- Swift 6.0 — all types must satisfy strict concurrency; `RouteSyncService` is `@MainActor`
- Binary format: flat `[Double]` sequence, `lat0 lon0 lat1 lon1 …`, native byte order, 16 bytes per coordinate
- Corrupted files (byte count not a multiple of 16) are silently skipped and treated as a cache miss
- Cache directory: `<Caches>/RouteCache/` — created on first write, never pruned
- GPS workout types: `.cycling`, `.running`, `.walking` only
- `fetchAllGPSWorkouts()` uses `HKObjectQueryNoLimit` with no date floor
- No cache invalidation, size limits, or eviction in scope

## Review Focus

1. **Corrupted `.dat` file** (byte count not a multiple of 16) — `coordinates(for:)` must return `nil`, not crash; covered in Task 1 tests.
2. **First launch with zero cached routes while sync is running** — view must show a `ProgressView`, not a blank `ContentUnavailableView`; the condition is `allCoordinates.isEmpty && isSyncing`; covered in Task 4's state matrix.
3. **HealthKit returns an error from `fetchAllGPSWorkouts`** — `sync()` must not crash; `try?` swallows the error and returns `[]`; covered in Task 3 step.
4. **Workout route already cached on second launch** — `cachedUUIDs()` must correctly exclude it from the new-fetch set so it is never re-fetched; round-trip and UUID set tests in Task 1 exercise this path.
5. **Empty route returned for a new workout** (GPS off) — must not be written to cache or appended to `allCoordinates`; the `where !coords.isEmpty` guard in `sync()` ensures this; covered in Task 3 step.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Meridian/Helpers/RouteCache.swift` | Create | Binary file I/O for coordinate arrays |
| `Meridian/Helpers/RouteSyncService.swift` | Create | Load from cache + incremental HealthKit sync |
| `Meridian/Helpers/HealthKitWorkoutService.swift` | Modify | Add `fetchAllGPSWorkouts()` |
| `Meridian/Views/RoutesView.swift` | Modify | Observe `RouteSyncService`, show sync pill |
| `MeridianTests/RouteCacheTests.swift` | Create | Unit tests for binary round-trip and edge cases |

---

### Task 1: RouteCache

**Files:**
- Create: `Meridian/Helpers/RouteCache.swift`
- Create: `MeridianTests/RouteCacheTests.swift`

**Interfaces:**
- Produces:
  - `RouteCache.init(cacheDir: URL? = nil)` — `nil` uses `<Caches>/RouteCache/`
  - `RouteCache.store(_ coordinates: [CLLocationCoordinate2D], for uuid: UUID)`
  - `RouteCache.coordinates(for uuid: UUID) -> [CLLocationCoordinate2D]?`
  - `RouteCache.cachedUUIDs() -> Set<UUID>`

- [ ] **Step 1: Write the failing tests**

  Create `MeridianTests/RouteCacheTests.swift`:

  ```swift
  import Testing
  import Foundation
  import CoreLocation
  @testable import Meridian

  @Suite("RouteCache")
  struct RouteCacheTests {

      private func makeCache() -> RouteCache {
          let dir = FileManager.default.temporaryDirectory
              .appendingPathComponent(UUID().uuidString)
          return RouteCache(cacheDir: dir)
      }

      @Test("stores and retrieves coordinates round-trip")
      func roundTrip() {
          let cache = makeCache()
          let uuid = UUID()
          let coords = [
              CLLocationCoordinate2D(latitude: 37.5, longitude: -122.0),
              CLLocationCoordinate2D(latitude: 37.6, longitude: -121.9)
          ]
          cache.store(coords, for: uuid)
          let retrieved = cache.coordinates(for: uuid)
          #expect(retrieved?.count == 2)
          #expect(abs(retrieved![0].latitude  - 37.5)   < 0.000001)
          #expect(abs(retrieved![0].longitude - (-122.0)) < 0.000001)
          #expect(abs(retrieved![1].latitude  - 37.6)   < 0.000001)
          #expect(abs(retrieved![1].longitude - (-121.9)) < 0.000001)
      }

      @Test("returns nil for unknown UUID")
      func cacheMiss() {
          let cache = makeCache()
          #expect(cache.coordinates(for: UUID()) == nil)
      }

      @Test("cachedUUIDs returns all stored UUIDs")
      func cachedUUIDs() {
          let cache = makeCache()
          let uuid1 = UUID()
          let uuid2 = UUID()
          cache.store([CLLocationCoordinate2D(latitude: 0, longitude: 0)], for: uuid1)
          cache.store([CLLocationCoordinate2D(latitude: 1, longitude: 1)], for: uuid2)
          let uuids = cache.cachedUUIDs()
          #expect(uuids.contains(uuid1))
          #expect(uuids.contains(uuid2))
          #expect(uuids.count == 2)
      }

      @Test("corrupted file returns nil without crashing")
      func corruptedFile() throws {
          let dir = FileManager.default.temporaryDirectory
              .appendingPathComponent(UUID().uuidString)
          try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
          let uuid = UUID()
          // 3 bytes is not a multiple of 16 — corrupted
          let fileURL = dir.appendingPathComponent(uuid.uuidString + ".dat")
          try Data([0x01, 0x02, 0x03]).write(to: fileURL)
          let cache = RouteCache(cacheDir: dir)
          #expect(cache.coordinates(for: uuid) == nil)
      }

      @Test("cachedUUIDs excludes non-UUID filenames")
      func cachedUUIDs_ignoresNonUUIDFiles() throws {
          let dir = FileManager.default.temporaryDirectory
              .appendingPathComponent(UUID().uuidString)
          try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
          // Write a junk file that isn't a valid UUID name
          try Data().write(to: dir.appendingPathComponent("junk.dat"))
          let cache = RouteCache(cacheDir: dir)
          #expect(cache.cachedUUIDs().isEmpty)
      }
  }
  ```

- [ ] **Step 2: Regenerate xcodeproj and run tests — expect RED**

  ```bash
  xcodegen generate
  xcodebuild test -scheme Meridian \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    2>&1 | grep -E "error:|cannot find|RouteCacheTests"
  ```

  Expected: compile errors — `RouteCache` not found.

- [ ] **Step 3: Create RouteCache.swift**

  Create `Meridian/Helpers/RouteCache.swift`:

  ```swift
  import Foundation
  import CoreLocation

  final class RouteCache: @unchecked Sendable {
      private let cacheDir: URL

      init(cacheDir: URL? = nil) {
          if let cacheDir {
              self.cacheDir = cacheDir
          } else {
              let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
              self.cacheDir = caches.appendingPathComponent("RouteCache")
          }
      }

      func store(_ coordinates: [CLLocationCoordinate2D], for uuid: UUID) {
          createDirectoryIfNeeded()
          var doubles: [Double] = []
          doubles.reserveCapacity(coordinates.count * 2)
          for coord in coordinates {
              doubles.append(coord.latitude)
              doubles.append(coord.longitude)
          }
          let data = doubles.withUnsafeBytes { Data($0) }
          try? data.write(to: fileURL(for: uuid))
      }

      func coordinates(for uuid: UUID) -> [CLLocationCoordinate2D]? {
          guard let data = try? Data(contentsOf: fileURL(for: uuid)) else { return nil }
          guard data.count % 16 == 0 else { return nil }
          return data.withUnsafeBytes { ptr -> [CLLocationCoordinate2D] in
              let doubles = Array(ptr.bindMemory(to: Double.self))
              return stride(from: 0, to: doubles.count, by: 2).map {
                  CLLocationCoordinate2D(latitude: doubles[$0], longitude: doubles[$0 + 1])
              }
          }
      }

      func cachedUUIDs() -> Set<UUID> {
          let urls = (try? FileManager.default.contentsOfDirectory(
              at: cacheDir, includingPropertiesForKeys: nil)) ?? []
          return Set(urls.compactMap { url -> UUID? in
              UUID(uuidString: url.deletingPathExtension().lastPathComponent)
          })
      }

      private func fileURL(for uuid: UUID) -> URL {
          cacheDir.appendingPathComponent(uuid.uuidString).appendingPathExtension("dat")
      }

      private func createDirectoryIfNeeded() {
          try? FileManager.default.createDirectory(
              at: cacheDir, withIntermediateDirectories: true)
      }
  }
  ```

- [ ] **Step 4: Regenerate xcodeproj and run tests — expect GREEN**

  ```bash
  xcodegen generate
  xcodebuild test -scheme Meridian \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    2>&1 | grep -E "RouteCache|✔|✗|Test run with"
  ```

  Expected: 5 RouteCache tests pass, full suite green.

- [ ] **Step 5: Commit**

  ```bash
  git add Meridian/Helpers/RouteCache.swift \
          MeridianTests/RouteCacheTests.swift \
          Meridian.xcodeproj/
  git commit -m "feat: add RouteCache binary file storage"
  ```

---

### Task 2: fetchAllGPSWorkouts

**Files:**
- Modify: `Meridian/Helpers/HealthKitWorkoutService.swift`

**Interfaces:**
- Consumes: existing `HKHealthStore` at `store`
- Produces: `HealthKitWorkoutService.fetchAllGPSWorkouts() async throws -> [HKWorkout]` — all `.cycling`, `.running`, `.walking` workouts, no date floor, no count limit, newest-first

- [ ] **Step 1: Add the method**

  In `Meridian/Helpers/HealthKitWorkoutService.swift`, add after `fetchRecentWorkouts`:

  ```swift
  func fetchAllGPSWorkouts() async throws -> [HKWorkout] {
      guard HKHealthStore.isHealthDataAvailable() else { return [] }
      let gpsTypes: Set<HKWorkoutActivityType> = [.cycling, .running, .walking]
      let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
      let all: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
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
      return all.filter { gpsTypes.contains($0.workoutActivityType) }
  }
  ```

- [ ] **Step 2: Build — expect success**

  ```bash
  xcodebuild build -scheme Meridian \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    2>&1 | grep -E "error:|BUILD"
  ```

  Expected: `BUILD SUCCEEDED`, no errors.

- [ ] **Step 3: Commit**

  ```bash
  git add Meridian/Helpers/HealthKitWorkoutService.swift
  git commit -m "feat: add fetchAllGPSWorkouts with no date or count limit"
  ```

---

### Task 3: RouteSyncService

**Files:**
- Create: `Meridian/Helpers/RouteSyncService.swift`

**Interfaces:**
- Consumes:
  - `RouteCache` (from Task 1)
  - `HealthKitWorkoutService.fetchAllGPSWorkouts() async throws -> [HKWorkout]` (from Task 2)
  - `WorkoutRouteService.fetchRoute(for: HKWorkout) async -> [CLLocationCoordinate2D]`
- Produces:
  - `RouteSyncService` — `@Observable @MainActor final class`
  - `RouteSyncService.allCoordinates: [[CLLocationCoordinate2D]]`
  - `RouteSyncService.isSyncing: Bool`
  - `RouteSyncService.syncProgress: (fetched: Int, total: Int)`
  - `RouteSyncService.sync() async`

- [ ] **Step 1: Create RouteSyncService.swift**

  Create `Meridian/Helpers/RouteSyncService.swift`:

  ```swift
  import Foundation
  import CoreLocation
  import Observation
  import HealthKit

  @Observable
  @MainActor
  final class RouteSyncService {
      private(set) var allCoordinates: [[CLLocationCoordinate2D]] = []
      private(set) var isSyncing = false
      private(set) var syncProgress: (fetched: Int, total: Int) = (0, 0)

      private let cache = RouteCache()
      private let workoutService = HealthKitWorkoutService()
      private let routeService = WorkoutRouteService()

      func sync() async {
          // 1. Load from cache immediately so the map renders before any HealthKit call.
          let cachedUUIDs = cache.cachedUUIDs()
          allCoordinates = cachedUUIDs.compactMap { cache.coordinates(for: $0) }

          isSyncing = true
          defer { isSyncing = false }

          // 2. Fetch all GPS workouts; swallow errors (returns [] on failure).
          let workouts = (try? await workoutService.fetchAllGPSWorkouts()) ?? []
          let newWorkouts = workouts.filter { !cachedUUIDs.contains($0.uuid) }
          syncProgress = (fetched: 0, total: newWorkouts.count)

          guard !newWorkouts.isEmpty else { return }

          // Capture services as locals — they are @unchecked Sendable and safe to
          // use from concurrent task closures without hopping back to the main actor.
          let routeService = self.routeService
          let cache = self.cache

          // 3. Fetch new routes concurrently; append each as it arrives.
          await withTaskGroup(of: (UUID, [CLLocationCoordinate2D]).self) { group in
              for workout in newWorkouts {
                  group.addTask {
                      let coords = await routeService.fetchRoute(for: workout)
                      return (workout.uuid, coords)
                  }
              }
              for await (uuid, coords) in group {
                  guard !coords.isEmpty else { continue }
                  cache.store(coords, for: uuid)
                  allCoordinates.append(coords)
                  syncProgress.fetched += 1
              }
          }
      }
  }
  ```

- [ ] **Step 2: Regenerate xcodeproj and build — expect success**

  ```bash
  xcodegen generate
  xcodebuild build -scheme Meridian \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    2>&1 | grep -E "error:|BUILD"
  ```

  Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

  ```bash
  git add Meridian/Helpers/RouteSyncService.swift Meridian.xcodeproj/
  git commit -m "feat: add RouteSyncService with cache-first load and incremental sync"
  ```

---

### Task 4: Wire RoutesView to RouteSyncService

**Files:**
- Modify: `Meridian/Views/RoutesView.swift`

**Interfaces:**
- Consumes:
  - `RouteSyncService.allCoordinates: [[CLLocationCoordinate2D]]`
  - `RouteSyncService.isSyncing: Bool`
  - `RouteSyncService.syncProgress: (fetched: Int, total: Int)`
  - `RouteSyncService.sync() async`
  - `routeMapRegion(for: [CLLocationCoordinate2D]) -> MKCoordinateRegion` (existing free function in `WorkoutRouteMapView.swift`)

- [ ] **Step 1: Replace RoutesView.swift**

  Overwrite `Meridian/Views/RoutesView.swift` with:

  ```swift
  import SwiftUI
  import HealthKit
  import MapKit
  import CoreLocation

  extension HKWorkoutActivityType {
      var isGPSTracked: Bool {
          switch self {
          case .cycling, .running, .walking: return true
          default: return false
          }
      }
  }

  struct RoutesView: View {
      @State private var sync = RouteSyncService()

      var body: some View {
          NavigationStack {
              content
                  .navigationTitle("Routes")
                  .navigationBarTitleDisplayMode(.inline)
          }
          .task { await sync.sync() }
      }

      @ViewBuilder
      private var content: some View {
          if sync.allCoordinates.isEmpty && sync.isSyncing {
              ProgressView("Loading routes…")
                  .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else if sync.allCoordinates.isEmpty {
              ContentUnavailableView(
                  "No Routes",
                  systemImage: "map",
                  description: Text("GPS workouts from your Apple Watch will appear here.")
              )
          } else {
              let flat = sync.allCoordinates.flatMap { $0 }
              ZStack(alignment: .top) {
                  Map(initialPosition: .region(routeMapRegion(for: flat))) {
                      ForEach(sync.allCoordinates.indices, id: \.self) { i in
                          MapPolyline(coordinates: sync.allCoordinates[i])
                              .stroke(Color.accentColor.opacity(0.8), lineWidth: 2)
                      }
                  }
                  .ignoresSafeArea(edges: .bottom)
                  if sync.isSyncing && !sync.allCoordinates.isEmpty {
                      syncPill
                  }
              }
          }
      }

      private var syncPill: some View {
          Text("Syncing \(sync.syncProgress.fetched) / \(sync.syncProgress.total)")
              .font(.system(size: 12, weight: .medium))
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .background(.ultraThinMaterial, in: Capsule())
              .padding(.top, 8)
      }
  }
  ```

- [ ] **Step 2: Run the full test suite — expect GREEN**

  ```bash
  xcodebuild test -scheme Meridian \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    2>&1 | grep -E "✔|✗|Test run with|TEST (SUCCEEDED|FAILED)"
  ```

  Expected: all tests pass (the `RoutesViewTests` GPS-filter tests still compile because `isGPSTracked` remains in `RoutesView.swift`).

- [ ] **Step 3: Verify state matrix manually in Simulator**

  Launch the app and observe these states:
  - **First launch / no cache**: spinner shown while `allCoordinates` is empty and syncing.
  - **After first sync**: map with all routes; pill disappears when `isSyncing` becomes false.
  - **Second launch**: map renders immediately from cache; pill appears briefly only if new workouts exist.

- [ ] **Step 4: Commit**

  ```bash
  git add Meridian/Views/RoutesView.swift
  git commit -m "feat: wire RoutesView to RouteSyncService for cache-first all-time routes"
  ```
