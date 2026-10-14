# Route Sync & Cache

2026-10-13

## Overview

Replace the 50-workout in-memory fetch with a persistent file cache and incremental sync. On every launch the Routes tab loads instantly from disk, then fetches any new Apple Watch rides in the background and adds them to the map live.

---

## Architecture

### RouteCache

Manages binary files in `Caches/RouteCache/<uuid>.dat`. Each file stores a flat sequence of IEEE-754 doubles: `lat0, lon0, lat1, lon1, …` (~16 bytes per coordinate, vs ~40 for JSON).

Public interface:
- `store(_ coordinates: [CLLocationCoordinate2D], for uuid: UUID)`
- `coordinates(for uuid: UUID) -> [CLLocationCoordinate2D]?` — returns nil on miss
- `cachedUUIDs() -> Set<UUID>`

Cache directory is created on first write. Files are never deleted automatically (route history is append-only).

### RouteSyncService

`@Observable` class. Owns `RouteCache` and a `WorkoutRouteService`. Holds:
- `allCoordinates: [[CLLocationCoordinate2D]]` — starts from cache, grows as sync runs
- `isSyncing: Bool`
- `syncProgress: (fetched: Int, total: Int)`

Sync algorithm:
1. Load all cached routes → populate `allCoordinates` immediately.
2. Fetch all GPS workout UUIDs from HealthKit (`HealthKitWorkoutService.fetchAllGPSWorkouts()`).
3. Subtract already-cached UUIDs → `newUUIDs`.
4. For each new UUID: fetch route coordinates via `WorkoutRouteService.fetchRoute(for:)`, store to cache, append to `allCoordinates`. Fetches run concurrently via `TaskGroup` — HealthKit handles internal rate limiting.
5. Set `isSyncing = false` when done.

`sync()` is safe to call on every launch — it is a no-op when nothing is new.

### HealthKitWorkoutService

New method: `fetchAllGPSWorkouts() async throws -> [HKWorkout]`

Queries HealthKit with no date floor and `HKObjectQueryNoLimit`, then filters results to `.cycling`, `.running`, `.walking` activity types. Sorted newest-first.

### RoutesView

- Creates and holds `RouteSyncService` as `@State`.
- On `.task`: calls `sync()`.
- Map renders all `allCoordinates` entries as `MapPolyline` overlays.
- While `isSyncing`: shows a compact pill overlay at the top — "Syncing N / Total" — that disappears when done.
- Empty state when `allCoordinates` is empty and `!isSyncing`.

---

## Binary Format

Each `.dat` file:
```
[Float64 lat][Float64 lon][Float64 lat][Float64 lon]...
```
All values in native byte order. File size = `coordinateCount * 16` bytes. Corrupted/truncated files (size not a multiple of 16) are silently skipped and treated as a cache miss.

---

## Sync Progress UI

A small rounded-rect pill, top-center of the map, visible only while `isSyncing`:
```
Syncing 12 / 47
```
Disappears (`.opacity(isSyncing ? 1 : 0)`) when sync completes.

---

## Files Touched

| File | Action |
|------|--------|
| `Meridian/Helpers/RouteCache.swift` | New |
| `Meridian/Helpers/RouteSyncService.swift` | New |
| `Meridian/Helpers/HealthKitWorkoutService.swift` | Add `fetchAllGPSWorkouts()` |
| `Meridian/Views/RoutesView.swift` | Drive sync, observe updates |

---

## Out of Scope

- Cache invalidation / re-fetching corrected routes
- Cache size limits or eviction
- Syncing non-GPS workout types
- Offline indicator when HealthKit is unavailable
