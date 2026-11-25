import XCTest
@testable import AppLogic

final class ScanFileChangeTests: XCTestCase {
    private func roundTrip(_ change: ScanFileChange) -> ScanFileChange? {
        let center = NotificationCenter()
        var received: ScanFileChange?
        let token = center.addObserver(forName: ScanFileChange.notificationName, object: nil, queue: nil) {
            received = ScanFileChange(notification: $0)
        }
        change.post(to: center)
        center.removeObserver(token)
        return received
    }

    func testEveryKindArrivesAsPosted() {
        for kind in [ScanFileChange.Kind.saved, .recovered, .deleted] {
            let change = ScanFileChange(kind: kind, fileName: "Kitchen.db")
            XCTAssertEqual(roundTrip(change), change)
        }
    }

    func testARenameCarriesBothNamesExactly() {
        let change = ScanFileChange(kind: .renamed, fileName: "Vesterbrogade 12 – kælder v1.2.db",
                                    previousFileName: "261125-101500.db")
        XCTAssertEqual(roundTrip(change), change)
    }

    func testUserInfoUsesPlainStringKeys() {
        let center = NotificationCenter()
        var info: [AnyHashable: Any]?
        let token = center.addObserver(forName: ScanFileChange.notificationName, object: nil, queue: nil) {
            info = $0.userInfo
        }
        ScanFileChange(kind: .renamed, fileName: "B.db", previousFileName: "A.db").post(to: center)
        center.removeObserver(token)
        XCTAssertEqual(info?["kind"] as? String, "renamed")
        XCTAssertEqual(info?["fileName"] as? String, "B.db")
        XCTAssertEqual(info?["previousFileName"] as? String, "A.db")
    }

    func testAnotherNotificationIsNotAScanFileChange() {
        XCTAssertNil(ScanFileChange(notification: Notification(name: Notification.Name("Other"))))
        XCTAssertNil(ScanFileChange(notification: Notification(name: ScanFileChange.notificationName,
                                                               object: nil, userInfo: ["kind": "exploded"])))
    }
}
