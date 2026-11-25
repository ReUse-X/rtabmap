//
//  ScannerHost.swift
//  RTABMapApp
//
//  Describes an app that shows the scanning screen inside its own interface.
//

import Foundation

/// Set on the scanning screen by an app that shows it inside its own interface. Nil in the standalone app.
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
