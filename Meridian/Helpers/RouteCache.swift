import Foundation
import CoreLocation

/// File-based route coordinate cache. `@unchecked Sendable` because `FileManager` I/O is
/// inherently not thread-safe; callers are responsible for serializing concurrent access.
/// `RouteSyncService` satisfies this contract by performing all reads and writes on the
/// `@MainActor` (via the `for await` loop in `sync()`).
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
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }
}
