import XCTest
@testable import AppLogic

final class PhotosFollowScanTests: StoreTestCase {
    let danish = "Vesterbrogade 12 – kælder v1.2.db"

    // MARK: Renamed in the Library

    func testARenamedScanKeepsItsPhotos() throws {
        let id = try makeSession(for: "Kitchen.db", photos: 2)
        try store.databaseMoved(from: "Kitchen.db", to: danish)
        XCTAssertEqual(try sessions(naming: danish).map(\.folder), [id])
        XCTAssertTrue(try sessions(naming: "Kitchen.db").isEmpty)
        XCTAssertEqual(store.attachSession(for: danish), id)
        XCTAssertEqual(store.currentPhotoCount(), 2)
    }

    func testMovingOntoAnotherScanDropsTheReplacedScansSession() throws {
        let moved = try makeSession(for: "A.db", photos: 1)
        let replaced = try makeSession(for: "B.db", photos: 3)
        try store.databaseMoved(from: "A.db", to: "B.db")
        XCTAssertEqual(try sessions(naming: "B.db").map(\.folder), [moved])
        XCTAssertFalse(try sessionsOnDisk().map(\.folder).contains(replaced))
    }

    func testMovingAScanWithoutPhotosStillDropsTheReplacedScansSession() throws {
        try makeSession(for: "B.db", photos: 3)
        try store.databaseMoved(from: "A.db", to: "B.db")
        XCTAssertTrue(try sessionsOnDisk().isEmpty)
    }

    func testMovingToTheSameNameChangesNothing() throws {
        let id = try makeSession(for: "A.db", photos: 1)
        try store.databaseMoved(from: "A.db", to: "A.db")
        XCTAssertEqual(try sessions(naming: "A.db").map(\.folder), [id])
        XCTAssertEqual(store.photos(in: id).count, 1)
    }

    // MARK: Recovered after a crash

    /// The app was relaunched, so no session is current when the recovered file gets its name.
    /// The next new scan wipes the temporary database's sessions; the recovered scan's photos must survive it.
    func testARecoveredScanKeepsItsPhotosAcrossARelaunchAndTheNextNewScan() throws {
        let id = try store.startNewSession(dbFilename: "rtabmap.tmp.db", appVersion: "test")
        try addPhoto()
        let relaunched = ManualPhotoStore(documentsDirectory: docs)
        try relaunched.databaseMoved(from: "rtabmap.tmp.db", to: "261125-101500.db")
        _ = try relaunched.startNewSession(dbFilename: "rtabmap.tmp.db", appVersion: "test")
        XCTAssertEqual(relaunched.attachSession(for: "261125-101500.db"), id)
        XCTAssertEqual(relaunched.currentPhotoCount(), 1)
    }

    // MARK: Two sessions naming one file, left behind by earlier versions

    func testAttachPicksTheNewestOfTwoSessionsNamingOneFile() throws {
        try writeSession(id: "OLDER", dbFilename: "A.db", createdAt: Date(timeIntervalSince1970: 1_000))
        try writeSession(id: "NEWER", dbFilename: "A.db", createdAt: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(store.attachSession(for: "A.db"), "NEWER")
    }

    func testAttachSettlesEqualDatesByTheSmallerId() throws {
        try writeSession(id: "BBBB", dbFilename: "A.db", createdAt: Date(timeIntervalSince1970: 1_000))
        try writeSession(id: "AAAA", dbFilename: "A.db", createdAt: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(store.attachSession(for: "A.db"), "AAAA")
    }

    // MARK: Saved

    func testSavingANewScanOverAnExistingOneLeavesOneSession() throws {
        let old = try makeSession(for: "Kitchen.db", photos: 3)
        let new = try store.startNewSession(dbFilename: "rtabmap.tmp.db", appVersion: "test")
        try addPhoto()
        touch("Kitchen.db")
        try store.recordSavedDB(filename: "Kitchen.db", previous: nil)
        XCTAssertEqual(try sessions(naming: "Kitchen.db").map(\.folder), [new])
        XCTAssertFalse(try sessionsOnDisk().map(\.folder).contains(old))
        XCTAssertEqual(store.currentPhotoCount(), 1)
    }

    /// An opened scan saved under a new name while its own file stays: both scans keep the photos.
    func testSavingAnOpenedScanUnderANewNameKeepsPhotosOnBoth() throws {
        let original = try makeSession(for: "Kitchen.db", photos: 2)
        touch("Kitchen.db")
        _ = store.attachSession(for: "Kitchen.db")
        touch(danish)                                   // the save wrote the new file
        try store.recordSavedDB(filename: danish, previous: "Kitchen.db")

        XCTAssertEqual(try sessions(naming: "Kitchen.db").map(\.folder), [original])
        XCTAssertEqual(store.photos(in: original).count, 2)
        let copies = try sessions(naming: danish)
        XCTAssertEqual(copies.count, 1)
        XCTAssertNotEqual(copies[0].folder, original)
        XCTAssertEqual(copies[0].json.sessionId, copies[0].folder)
        XCTAssertEqual(store.currentSessionId, copies[0].folder)
        XCTAssertEqual(store.currentPhotoCount(), 2)

        try addPhoto()                                  // from now on photos belong to the new scan only
        XCTAssertEqual(store.currentPhotoCount(), 3)
        XCTAssertEqual(store.photos(in: original).count, 2)
    }

    /// A scan saved once and then saved again under another name: the scanner renames the file,
    /// so the earlier name is gone and the session moves.
    func testSavingUnderANewNameWhenTheOldFileIsGoneMovesTheSession() throws {
        let id = try makeSession(for: "A.db", photos: 1)
        _ = store.attachSession(for: "A.db")
        touch("B.db")                                   // A.db does not exist
        try store.recordSavedDB(filename: "B.db", previous: "A.db")
        XCTAssertEqual(try sessionsOnDisk().map(\.folder), [id])
        XCTAssertEqual(try sessions(naming: "B.db").map(\.folder), [id])
    }

    func testSavingUnderTheSameNameKeepsTheSession() throws {
        let id = try makeSession(for: "A.db", photos: 1)
        touch("A.db")
        _ = store.attachSession(for: "A.db")
        try store.recordSavedDB(filename: "A.db", previous: "A.db")
        XCTAssertEqual(try sessionsOnDisk().map(\.folder), [id])
        XCTAssertEqual(store.currentPhotoCount(), 1)
    }

    func testSavingOverAScanWithPhotosWhenNoSessionIsCurrentDropsTheOldSession() throws {
        try makeSession(for: "Kitchen.db", photos: 3)
        touch("Kitchen.db")
        try store.recordSavedDB(filename: "Kitchen.db", previous: nil)
        XCTAssertTrue(try sessionsOnDisk().isEmpty)
    }
}
