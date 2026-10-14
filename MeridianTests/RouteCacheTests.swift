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
        #expect(abs(retrieved![0].latitude  - 37.5)    < 0.000001)
        #expect(abs(retrieved![0].longitude - (-122.0)) < 0.000001)
        #expect(abs(retrieved![1].latitude  - 37.6)    < 0.000001)
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
        try Data().write(to: dir.appendingPathComponent("junk.dat"))
        let cache = RouteCache(cacheDir: dir)
        #expect(cache.cachedUUIDs().isEmpty)
    }
}
