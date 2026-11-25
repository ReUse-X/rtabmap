import XCTest
@testable import AppLogic

/// A store working in a temporary folder that stands in for the app's Documents.
class StoreTestCase: XCTestCase {
    var docs: URL!
    var store: ManualPhotoStore!

    override func setUpWithError() throws {
        docs = FileManager.default.temporaryDirectory.appendingPathComponent("docs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        store = ManualPhotoStore(documentsDirectory: docs)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: docs)
    }

    /// An empty file standing in for a scan.
    func touch(_ name: String) {
        FileManager.default.createFile(atPath: docs.appendingPathComponent(name).path, contents: Data())
    }

    /// A session for `dbFilename` holding `photos` photos, left detached. Returns its id.
    @discardableResult
    func makeSession(for dbFilename: String, photos: Int = 0) throws -> String {
        let id = try store.startNewSession(dbFilename: dbFilename, appVersion: "test")
        for _ in 0..<photos { try addPhoto() }
        store.detach()
        return id
    }

    /// One photo in the current session.
    func addPhoto() throws {
        let sessionId = store.currentSessionId ?? ""
        _ = try store.writePhoto(jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9])) { id, name, bytes, sha in
            PhotoSidecar(
                id: id, sessionId: sessionId, capturedAt: Date(), arkitTimestamp: 0,
                camera: CameraMeta(transform: [], intrinsics: .init(fx: 0, fy: 0, cx: 0, cy: 0),
                                   imageSize: .init(width: 0, height: 0),
                                   orientation: "portrait", trackingState: "normal"),
                env: nil, gps: nil, file: FileMeta(name: name, bytes: bytes, sha256: sha),
                user: .empty, schemaVersion: 1)
        }
    }

    /// A session folder written by hand, for states the store itself never produces.
    func writeSession(id: String, dbFilename: String, createdAt: Date) throws {
        let folder = docs.appendingPathComponent("ManualPhotos").appendingPathComponent(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = SessionJSON(sessionId: id, createdAt: createdAt, dbFilename: dbFilename,
                               appVersion: "test", schemaVersion: 1)
        try PhotoMetadataCodec.encoder().encode(json).write(to: folder.appendingPathComponent("session.json"))
    }

    /// Every session on disk: its folder name and what its session.json says.
    func sessionsOnDisk() throws -> [(folder: String, json: SessionJSON)] {
        let root = docs.appendingPathComponent("ManualPhotos")
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: root.path).sorted().compactMap { name in
            let file = root.appendingPathComponent(name).appendingPathComponent("session.json")
            guard let data = try? Data(contentsOf: file) else { return nil }
            return (name, try PhotoMetadataCodec.decoder().decode(SessionJSON.self, from: data))
        }
    }

    func sessions(naming dbFilename: String) throws -> [(folder: String, json: SessionJSON)] {
        try sessionsOnDisk().filter { $0.json.dbFilename == dbFilename }
    }
}
