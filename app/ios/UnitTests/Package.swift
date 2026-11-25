// swift-tools-version:5.9
import PackageDescription

// Unit tests for the parts of the iOS app that need no device. The sources are
// symbolic links to the app's own files, so the tests always build what the app builds.
let package = Package(
    name: "AppLogic",
    platforms: [.macOS(.v13), .iOS(.v15)],
    targets: [
        .target(name: "AppLogic"),
        .testTarget(name: "AppLogicTests", dependencies: ["AppLogic"]),
    ]
)
