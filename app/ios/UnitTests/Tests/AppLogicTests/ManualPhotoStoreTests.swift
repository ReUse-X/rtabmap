import XCTest
@testable import AppLogic

final class ManualPhotoStoreTests: StoreTestCase {
    func testNewSessionNamesTheDatabaseAndBecomesCurrent() throws {
        let id = try store.startNewSession(dbFilename: "rtabmap.tmp.db", appVersion: "test")
        XCTAssertEqual(store.currentSessionId, id)
        let all = try sessionsOnDisk()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].folder, id)
        XCTAssertEqual(all[0].json.sessionId, id)
        XCTAssertEqual(all[0].json.dbFilename, "rtabmap.tmp.db")
    }

    func testNewSessionReplacesEarlierSessionsOfTheSameFile() throws {
        try makeSession(for: "rtabmap.tmp.db", photos: 1)
        let second = try store.startNewSession(dbFilename: "rtabmap.tmp.db", appVersion: "test")
        XCTAssertEqual(try sessionsOnDisk().map(\.folder), [second])
    }

    func testAttachFindsTheSessionOfAFile() throws {
        let id = try makeSession(for: "Kitchen.db", photos: 2)
        XCTAssertEqual(store.attachSession(for: "Kitchen.db"), id)
        XCTAssertEqual(store.currentPhotoCount(), 2)
    }

    func testAttachToAFileWithoutASessionDetaches() throws {
        try makeSession(for: "Kitchen.db")
        _ = store.attachSession(for: "Kitchen.db")
        XCTAssertNil(store.attachSession(for: "Other.db"))
        XCTAssertNil(store.currentSessionId)
    }

    func testFirstSaveRepointsTheCurrentSession() throws {
        let id = try store.startNewSession(dbFilename: "rtabmap.tmp.db", appVersion: "test")
        try addPhoto()
        touch("Kitchen.db")
        try store.recordSavedDB(filename: "Kitchen.db")
        XCTAssertEqual(try sessions(naming: "Kitchen.db").map(\.folder), [id])
        XCTAssertTrue(try sessions(naming: "rtabmap.tmp.db").isEmpty)
        XCTAssertEqual(store.currentPhotoCount(), 1)
    }

    func testDeleteSessionRemovesTheFolder() throws {
        try makeSession(for: "Kitchen.db", photos: 1)
        store.deleteSession(for: "Kitchen.db")
        XCTAssertTrue(try sessionsOnDisk().isEmpty)
    }
}
