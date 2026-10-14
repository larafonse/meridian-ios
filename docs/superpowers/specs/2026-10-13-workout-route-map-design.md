# Workout Route Map

2026-10-13

## Overview

Add a route map view to Meridian that displays the GPS track recorded by Apple Watch for outdoor workouts (cycling, running, walking). The map is accessed via a button in `WorkoutHistorySheet` on eligible workout rows and rendered as a full-screen sheet.

No live tracking, elevation charts, or sharing — display only.

---

## Architecture

Three additions to the existing codebase:

### 1. `WorkoutRouteService` (new helper)

Queries HealthKit for the `HKWorkoutRoute` associated with a given `HKWorkout` and returns the accumulated `[CLLocationCoordinate2D]`.

- Takes an `HKWorkout` (looked up by UUID from `WorkoutSession.healthKitUUID`)
- Uses `HKAnchoredObjectQuery` to find the route series, then `HKWorkoutRouteQuery` to stream location batches
- Returns an empty array (not an error) when no route is present — the view handles that gracefully

### 2. `WorkoutRouteMapView` (new view)

Full-screen sheet presenting the route on a map.

- SwiftUI `Map` + `MapPolyline` (native iOS 17, no `UIViewRepresentable` needed)
- Region auto-fits to the route's coordinate bounding box with padding
- Start pin (green) and end pin (red)
- Small stats bar at bottom: distance and duration pulled from the `HKWorkout`
- Loading state while route is being fetched
- "No route data available" state when HealthKit returns no coordinates

### 3. `WorkoutHistorySheet` (modified)

Adds a map icon button to the section header for GPS-capable workout types: cycling, running, walking.

- Button appears only when `session.workoutType` is one of the GPS types
- Tapping presents `WorkoutRouteMapView` as a sheet, passing the `healthKitUUID` to look up the workout
- No pre-flight check for route existence — the map view handles the empty state

---

## HealthKit Integration

### Route fetching flow

```
WorkoutSession.healthKitUUID
  → HKSampleQuery to find the HKWorkout
  → HKAnchoredObjectQuery on HKSeriesType.workoutRoute() predicated to that workout
  → HKWorkoutRouteQuery to stream CLLocation batches
  → Accumulate into [CLLocationCoordinate2D]
```

### Permissions

`HKSeriesType.workoutRoute()` must be added to the read set in `HealthKitActivityService.requestAuthorization()`. No CoreLocation permissions are required — reading routes from HealthKit does not trigger location prompts.

---

## Map UI

- Route rendered as a `MapPolyline` styled in the app's accent color
- Map style: `.standard` (clean, matches the app's minimal aesthetic)
- Region calculated from min/max lat/long of all coordinates + ~15% padding
- Start/end markers use `Annotation` with SF Symbol circles (green `circle.fill` / red `circle.fill`)
- Stats bar: distance formatted as km/miles (respects locale), duration as `h:mm`
- Dismiss via swipe or a toolbar close button

---

## Files Touched

| File | Change |
|------|--------|
| `Meridian/Helpers/WorkoutRouteService.swift` | New — HealthKit route query |
| `Meridian/Views/WorkoutRouteMapView.swift` | New — map sheet |
| `Meridian/Views/WorkoutHistorySheet.swift` | Add map button to GPS workout rows |
| `Meridian/Helpers/ActivityService.swift` | Add `HKSeriesType.workoutRoute()` to read permissions |

---

## GPS-Capable Workout Types

The map button appears for: `cycling`, `running`, `walking`. These are the workout types in Meridian's catalogue where Apple Watch records GPS routes.

---

## Out of Scope

- Live GPS tracking during a workout
- Elevation profile chart
- Route sharing or export
- Map style switcher (satellite/hybrid)
- Multiple routes on one map
