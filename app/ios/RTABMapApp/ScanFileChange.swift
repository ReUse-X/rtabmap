import Foundation

/// What happened to a scan file in the app's Documents folder. Posted on the main thread, after the
/// change is complete on disk.
struct ScanFileChange: Equatable {
    enum Kind: String { case saved, renamed, recovered, deleted }

    let kind: Kind
    /// The file's name now, with its extension ("Kitchen.db"). For `.deleted`, the name it had.
    let fileName: String
    /// For `.renamed`, the name before. Otherwise nil.
    let previousFileName: String?

    static let notificationName = Notification.Name("ScanFileChangeNotification")

    init(kind: Kind, fileName: String, previousFileName: String? = nil) {
        self.kind = kind
        self.fileName = fileName
        self.previousFileName = previousFileName
    }

    /// Nil when `notification` is not a scan file change.
    init?(notification: Notification) {
        guard notification.name == ScanFileChange.notificationName,
              let info = notification.userInfo,
              let rawKind = info["kind"] as? String,
              let kind = Kind(rawValue: rawKind),
              let fileName = info["fileName"] as? String else {
            return nil
        }
        self.init(kind: kind, fileName: fileName, previousFileName: info["previousFileName"] as? String)
    }

    func post(to center: NotificationCenter = .default) {
        var info: [String: String] = ["kind": kind.rawValue, "fileName": fileName]
        if let previousFileName = previousFileName {
            info["previousFileName"] = previousFileName
        }
        let name = ScanFileChange.notificationName
        if Thread.isMainThread {
            center.post(name: name, object: nil, userInfo: info)
        } else {
            DispatchQueue.main.async {
                center.post(name: name, object: nil, userInfo: info)
            }
        }
    }
}
