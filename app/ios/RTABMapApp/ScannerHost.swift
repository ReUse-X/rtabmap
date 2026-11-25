//
//  ScannerHost.swift
//  RTABMapApp
//
//  Describes an app that shows the scanning screen inside its own interface.
//

import Foundation

/// What an app that shows the scanning screen inside its own interface tells the screen. The standalone
/// app does not use it.
///
/// Hosting the screen:
/// - Ship `Settings.bundle` in the app. The screen reads its settings from `UserDefaults.standard` and
///   expects every key to have a value; when hosted it registers the bundle's default values itself
///   before it reads them.
/// - Create the screen as the initial view controller of the "Main" storyboard, set its `host`, and
///   present it full screen without animation: the initial action starts once the screen has appeared.
/// - Have at most one screen alive at a time, and create a new one for every opening.
/// - The user leaves through "Close Scanner" in the screen's menu. The screen then tears itself down
///   (`ViewController.tearDown()`) and calls `didClose`; take the screen off display right there. Until
///   then the scanner may still have a scan file open.
/// - While `host` is set, the screen ignores `dismiss(animated:completion:)` called on the screen itself,
///   because the screen makes that call to close its own alerts. To take the screen away for another
///   reason, call `tearDown()` first and dismiss the screen from the presenting controller only if it
///   returned true.
struct ScannerHost {
    enum InitialAction {
        case newScan       // start a new scan with the camera on, as "New Scan" on the welcome screen does
        case open(URL)     // open this scan file, as picking it in the Library does
    }
    /// What the screen does the first time it appears, instead of showing the welcome screen.
    var initialAction: InitialAction
    /// Called on the main thread after the user chose "Close Scanner" and the screen was torn down.
    /// The host removes the screen.
    var didClose: () -> Void
}
