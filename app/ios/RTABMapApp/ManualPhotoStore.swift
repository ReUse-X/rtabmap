//
//  ManualPhotoStore.swift
//  RTABMapApp
//
//  Owns the Documents/ManualPhotos/<sessionId>/ layout:
//    session.json
//    <filename>.jpg
//    <filename>.json
//

import Foundation
import CommonCrypto

/// Singleton store for manual-photo sessions on disk.
///
/// Threading contract: the store is **not** internally synchronized. Callers must
/// serialize access — typically the main thread for session-lifecycle calls
/// (`startNewSession` / `attachSession` / `detach` / `deleteSession`) and a
/// dedicated background queue for `writePhoto`. `currentSessionId` is read in
/// both contexts; callers must not mutate it from a background queue while a
/// main-thread lifecycle call is in flight.
final class ManualPhotoStore {

    static let shared = ManualPhotoStore()

    private let rootFolderName = "ManualPhotos"
    private let sessionFileName = "session.json"
    private let schemaVersion = 1

    private let fm = FileManager.default

    /// The folder that holds `ManualPhotos`. `nil` means the app's Documents folder.
    private let documentsDirectory: URL?

    init(documentsDirectory: URL? = nil) {
        self.documentsDirectory = documentsDirectory
    }

    /// Current session id. `nil` until `startNewSession` or `attachSession` is called.
    private(set) var currentSessionId: String?

    // MARK: - Paths

    /// The folder that holds `ManualPhotos` and the scan files themselves.
    private var documentsURL: URL {
        documentsDirectory ?? fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var rootURL: URL {
        documentsURL.appendingPathComponent(rootFolderName, isDirectory: true)
    }

    private func sessionURL(_ sessionId: String) -> URL {
        rootURL.appendingPathComponent(sessionId, isDirectory: true)
    }

    func currentSessionURL() -> URL? {
        guard let id = currentSessionId else { return nil }
        return sessionURL(id)
    }

    private func ensureDir(_ url: URL) throws {
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - Session lifecycle

    /// Delete the tmp session folder matching `dbFilename`, then mint a new session folder.
    /// Call this from `newScan()` when the rtabmap tmp DB is wiped.
    @discardableResult
    func startNewSession(dbFilename: String?, appVersion: String) throws -> String {
        try ensureDir(rootURL)

        // Delete any prior folders that point at the same tmp dbFilename (keeps Documents/ tidy).
        if let dbFilename = dbFilename {
            for folder in try existingSessionFolders() {
                if let s = try? readSessionJSON(at: folder), s.dbFilename == dbFilename {
                    try? fm.removeItem(at: folder)
                }
            }
        }

        let id = UUID().uuidString
        let url = sessionURL(id)
        try ensureDir(url)

        let session = SessionJSON(
            sessionId: id,
            createdAt: Date(),
            dbFilename: dbFilename,
            appVersion: appVersion,
            schemaVersion: schemaVersion
        )
        try writeSessionJSON(session, at: url)
        currentSessionId = id
        return id
    }

    /// Re-attach to an existing session folder for a saved DB.
    /// Returns the sessionId if found, else nil.
    /// When several sessions name the file, attaches the one with the latest `createdAt`;
    /// equal dates are settled by the smaller `sessionId`.
    @discardableResult
    func attachSession(for dbFilename: String) -> String? {
        guard let candidates = try? sessions(naming: dbFilename) else { return nil }
        let chosen = candidates.min { a, b in
            if a.session.createdAt != b.session.createdAt {
                return a.session.createdAt > b.session.createdAt
            }
            return a.session.sessionId < b.session.sessionId
        }
        currentSessionId = chosen?.session.sessionId
        return currentSessionId
    }

    /// The scan file `oldFilename` is now called `newFilename`: it was renamed, or recovered under a new name.
    /// Its sessions follow it. Nothing is deleted: a session that already names `newFilename` is left as it is.
    /// Works without a current session.
    func databaseMoved(from oldFilename: String, to newFilename: String) throws {
        guard oldFilename != newFilename else { return }
        for var entry in try sessions(naming: oldFilename) {
            entry.session.dbFilename = newFilename
            try writeSessionJSON(entry.session, at: entry.folder)
        }
    }

    /// The current session's scan was saved as `filename`. `previous` is the file name the scan had before
    /// this save, nil for a scan that was never saved. `overwroteExisting` is true when the save replaced a
    /// file that already had that name, which the user confirmed before saving.
    /// If `previous` is a different name whose file still exists, the save made a second scan: `previous`
    /// keeps the current session, and `filename` gets a copy of it that becomes current. Otherwise the
    /// current session now names `filename`.
    /// When `overwroteExisting` is true and the replaced file was another scan (`previous` is not
    /// `filename`), the other sessions that name `filename` belonged to that scan and are deleted.
    /// In every other case nothing is deleted: a scan saved under its own name replaces only itself.
    func recordSavedDB(filename: String, previous: String? = nil, overwroteExisting: Bool = false) throws {
        // Listed before the current session or its copy takes the name, so neither is ever among them.
        let replaced = overwroteExisting && previous != filename
            ? try sessions(naming: filename).filter { $0.session.sessionId != currentSessionId }
            : []

        guard let url = currentSessionURL() else {
            try removeSessions(replaced)
            return
        }
        var s = try readSessionJSON(at: url)

        if let previous = previous, previous != filename,
           fm.fileExists(atPath: documentsURL.appendingPathComponent(previous).path) {
            // The original file keeps the current session whatever happens, so the replaced sessions
            // go first: a copy that fails then leaves no other scan's photos on the saved file.
            try removeSessions(replaced)
            currentSessionId = try copySession(s, from: url, naming: filename)
        } else {
            // The current session takes the new name before anything is deleted: if a deletion fails
            // or the app stops, the saved scan's photos already name the saved file.
            s.dbFilename = filename
            try writeSessionJSON(s, at: url)
            try removeSessions(replaced)
        }
    }

    /// Clear the current session pointer without deleting files (e.g. after opening a saved DB).
    func detach() {
        currentSessionId = nil
    }

    /// Delete the session folder for the given dbFilename (if any).
    func deleteSession(for dbFilename: String) {
        guard let folders = try? existingSessionFolders() else { return }
        for folder in folders {
            if let s = try? readSessionJSON(at: folder), s.dbFilename == dbFilename {
                try? fm.removeItem(at: folder)
                if currentSessionId == s.sessionId { currentSessionId = nil }
            }
        }
    }

    // MARK: - Photo write

    struct WriteResult {
        let jpegURL: URL
        let jsonURL: URL
        let sidecar: PhotoSidecar
    }

    /// Synchronous on an arbitrary queue. Callers should dispatch off the main thread.
    func writePhoto(jpeg: Data, sidecarBuilder: (_ id: String, _ filename: String, _ bytes: Int, _ sha: String) -> PhotoSidecar) throws -> WriteResult {
        guard let sessionId = currentSessionId else {
            throw NSError(domain: "ManualPhotoStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "No active session"])
        }
        let folder = sessionURL(sessionId)
        try ensureDir(folder)

        let shortId = String(UUID().uuidString.prefix(8)).lowercased()
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd'T'HH-mm-ss.SSS"
        df.timeZone = TimeZone(identifier: "UTC")
        let stamp = df.string(from: Date())

        let base = "\(stamp)_\(shortId)"
        let jpegURL = folder.appendingPathComponent("\(base).jpg")
        let jsonURL = folder.appendingPathComponent("\(base).json")

        let sha = sha256Hex(data: jpeg)
        let sidecar = sidecarBuilder(shortId, "\(base).jpg", jpeg.count, sha)
        let jsonData = try PhotoMetadataCodec.encoder().encode(sidecar)

        try atomicWrite(data: jpeg, to: jpegURL)
        try atomicWrite(data: jsonData, to: jsonURL)

        return WriteResult(jpegURL: jpegURL, jsonURL: jsonURL, sidecar: sidecar)
    }

    /// Overwrite the sidecar JSON for an already-saved photo (used by the metadata editor).
    func updateSidecar(_ updated: PhotoSidecar, for jpegURL: URL) throws {
        let jsonURL = jpegURL.deletingPathExtension().appendingPathExtension("json")
        let jsonData = try PhotoMetadataCodec.encoder().encode(updated)
        try atomicWrite(data: jsonData, to: jsonURL)
    }

    func deletePhoto(jpegURL: URL) {
        let jsonURL = jpegURL.deletingPathExtension().appendingPathExtension("json")
        try? fm.removeItem(at: jpegURL)
        try? fm.removeItem(at: jsonURL)
    }

    // MARK: - Read

    struct PhotoEntry {
        let jpegURL: URL
        let sidecar: PhotoSidecar
    }

    /// All photos in the given session folder, newest first.
    func photos(in sessionId: String) -> [PhotoEntry] {
        let url = sessionURL(sessionId)
        guard let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        let jpegs = items
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
        return jpegs.compactMap { j in
            let sidecarURL = j.deletingPathExtension().appendingPathExtension("json")
            guard let data = try? Data(contentsOf: sidecarURL),
                  let s = try? PhotoMetadataCodec.decoder().decode(PhotoSidecar.self, from: data) else {
                return nil
            }
            return PhotoEntry(jpegURL: j, sidecar: s)
        }
    }

    func currentPhotos() -> [PhotoEntry] {
        guard let id = currentSessionId else { return [] }
        return photos(in: id)
    }

    func currentPhotoCount() -> Int {
        currentPhotos().count
    }

    // MARK: - Helpers

    private func existingSessionFolders() throws -> [URL] {
        guard fm.fileExists(atPath: rootURL.path) else { return [] }
        return try fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    /// Every session whose session.json names `dbFilename`, with its folder.
    private func sessions(naming dbFilename: String) throws -> [(folder: URL, session: SessionJSON)] {
        try existingSessionFolders().compactMap { folder in
            guard let s = try? readSessionJSON(at: folder), s.dbFilename == dbFilename else { return nil }
            return (folder, s)
        }
    }

    private func removeSessions(_ entries: [(folder: URL, session: SessionJSON)]) throws {
        for entry in entries {
            try fm.removeItem(at: entry.folder)
        }
    }

    /// Copies the session `session`, stored in `source`, to a new session that names `dbFilename`.
    /// Returns the new session's id.
    private func copySession(_ session: SessionJSON, from source: URL, naming dbFilename: String) throws -> String {
        let id = UUID().uuidString
        let target = sessionURL(id)
        try fm.createDirectory(at: target, withIntermediateDirectories: false)
        do {
            // session.json is written before anything else: a copy cut short by a crash then names
            // the new file, and the old file keeps a single, complete session.
            var copy = session
            copy.sessionId = id
            copy.createdAt = Date()
            copy.dbFilename = dbFilename
            try writeSessionJSON(copy, at: target)

            // The photos and their JSON files are copied as they are: each photo's JSON keeps
            // the sessionId it was captured under.
            let items = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            for item in items where item.lastPathComponent != sessionFileName {
                try fm.copyItem(at: item, to: target.appendingPathComponent(item.lastPathComponent))
            }
        } catch {
            try? fm.removeItem(at: target)
            throw error
        }
        return id
    }

    private func readSessionJSON(at folder: URL) throws -> SessionJSON {
        let url = folder.appendingPathComponent(sessionFileName)
        let data = try Data(contentsOf: url)
        return try PhotoMetadataCodec.decoder().decode(SessionJSON.self, from: data)
    }

    private func writeSessionJSON(_ s: SessionJSON, at folder: URL) throws {
        let url = folder.appendingPathComponent(sessionFileName)
        let data = try PhotoMetadataCodec.encoder().encode(s)
        try atomicWrite(data: data, to: url)
    }

    private func atomicWrite(data: Data, to url: URL) throws {
        // Data.write(.atomic) already does a tmp-write-then-rename — crash-safe with no extra staging.
        try data.write(to: url, options: .atomic)
    }

    private func sha256Hex(data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
