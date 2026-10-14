import Testing
import MapKit
import CoreLocation
@testable import Meridian

@Suite("WorkoutRouteMapView helpers")
struct WorkoutRouteMapViewTests {

    // MARK: - routeMapRegion

    @Test("center is the midpoint of the bounding box")
    func mapRegion_centerIsMidpoint() {
        let coords = [
            CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            CLLocationCoordinate2D(latitude: 38.0, longitude: -121.0)
        ]
        let region = routeMapRegion(for: coords)
        #expect(abs(region.center.latitude - 37.5) < 0.001)
        #expect(abs(region.center.longitude - (-121.5)) < 0.001)
    }

    @Test("span has 30% padding around the bounding box")
    func mapRegion_spanHas30PercentPadding() {
        let coords = [
            CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            CLLocationCoordinate2D(latitude: 38.0, longitude: -121.0)
        ]
        let region = routeMapRegion(for: coords)
        // raw delta 1.0 * 1.3 = 1.3
        #expect(abs(region.span.latitudeDelta - 1.3) < 0.001)
        #expect(abs(region.span.longitudeDelta - 1.3) < 0.001)
    }

    @Test("single coordinate uses minimum span to avoid zero-span crash")
    func mapRegion_singleCoordinate_usesMinimumSpan() {
        let coords = [CLLocationCoordinate2D(latitude: 37.5, longitude: -122.0)]
        let region = routeMapRegion(for: coords)
        #expect(abs(region.center.latitude - 37.5) < 0.001)
        #expect(abs(region.center.longitude - (-122.0)) < 0.001)
        #expect(region.span.latitudeDelta >= 0.005)
        #expect(region.span.longitudeDelta >= 0.005)
    }

    @Test("empty coordinates returns a non-zero default region without crashing")
    func mapRegion_emptyCoordinates_returnsDefaultRegion() {
        let region = routeMapRegion(for: [])
        #expect(region.span.latitudeDelta > 0)
        #expect(region.span.longitudeDelta > 0)
    }

    // MARK: - formatRouteDuration

    @Test("duration under one hour shows m:ss")
    func formatDuration_underOneHour() {
        #expect(formatRouteDuration(0) == "0:00")
        #expect(formatRouteDuration(65) == "1:05")
        #expect(formatRouteDuration(3599) == "59:59")
    }

    @Test("duration one hour or more shows h:mm:ss")
    func formatDuration_oneHourOrMore() {
        #expect(formatRouteDuration(3600) == "1:00:00")
        #expect(formatRouteDuration(3661) == "1:01:01")
        #expect(formatRouteDuration(7322) == "2:02:02")
    }
}
