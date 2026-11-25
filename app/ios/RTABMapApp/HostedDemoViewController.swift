//
//  HostedDemoViewController.swift
//  RTABMapApp
//
//  A stand-in host app, compiled into Debug builds only and started with the launch argument
//  -HostedDemo. It shows the scanning screen the way an embedding app would, and logs the scan
//  file notifications and what is left in memory after the screen closes.
//

#if DEBUG
import UIKit
import os

class HostedDemoViewController: UIViewController {

    private static let ignoredFiles: Set<String> = ["rtabmap.tmp.db", "rtabmap.tmp.recovery.db"]

    private let openLatestButton = UIButton(type: .system)
    private let logView = UITextView()
    private var latestScan: URL?
    private var changeObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let newButton = makeButton("New Scan", action: #selector(newScan))
        let missingButton = makeButton("Open Missing Scan", action: #selector(openMissingScan))
        openLatestButton.setTitle("Open Latest Scan", for: .normal)
        openLatestButton.addTarget(self, action: #selector(openLatestScan), for: .touchUpInside)

        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logView.backgroundColor = .secondarySystemBackground

        let stack = UIStackView(arrangedSubviews: [newButton, openLatestButton, missingButton, logView])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),
        ])

        changeObserver = NotificationCenter.default.addObserver(
            forName: ScanFileChange.notificationName, object: nil, queue: .main) { [weak self] notification in
            guard let change = ScanFileChange(notification: notification) else { return }
            var line = "\(change.kind.rawValue) \(change.fileName)"
            if let previous = change.previousFileName {
                line += " (was \(previous))"
            }
            self?.log(line)
        }
        updateLatestScan()
    }

    deinit {
        if let observer = changeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // The scans change while the scanner is up, so look again each time this screen appears.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateLatestScan()
    }

    private func makeButton(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func updateLatestScan() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: documentsURL, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
        latestScan = files
            .filter { $0.pathExtension == "db" && !Self.ignoredFiles.contains($0.lastPathComponent) }
            .max { modified($0) < modified($1) }
        openLatestButton.isEnabled = latestScan != nil
    }

    private func log(_ line: String) {
        logView.text += line + "\n"
    }

    @objc private func newScan() {
        show(.newScan)
    }

    @objc private func openLatestScan() {
        guard let url = latestScan else { return }
        show(.open(url))
    }

    @objc private func openMissingScan() {
        show(.open(documentsURL.appendingPathComponent("t-missing.db")))
    }

    private func show(_ action: ScannerHost.InitialAction) {
        let freeBefore = os_proc_available_memory() / 1_048_576
        let scanner = UIStoryboard(name: "Main", bundle: nil).instantiateInitialViewController() as! ViewController
        weak var weakScanner = scanner
        scanner.host = ScannerHost(initialAction: action, didClose: { [weak self] in
            self?.dismiss(animated: false)
            // The scanner can keep the screen alive for up to five seconds after closing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                let freeAfter = os_proc_available_memory() / 1_048_576
                self?.log("Scanner released: \(weakScanner == nil ? "yes" : "no")")
                self?.log("Free memory before/after: \(freeBefore) / \(freeAfter) MB")
            }
        })
        scanner.modalPresentationStyle = .fullScreen
        present(scanner, animated: false)
    }
}
#endif
