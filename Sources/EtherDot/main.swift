import AppKit
import SwiftUI
import EtherDotCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: NetworkMonitor!
    private var wifi: WiFiController!
    private var location: LocationPermission!
    private var launchAtLogin: LaunchAtLogin!
    private var updater: Updater!
    private var settings: SettingsWindowController!
    private var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.registerDefaults()
        let demo = CommandLine.arguments.contains("--demo")
        monitor = NetworkMonitor(demo: demo)
        wifi = WiFiController(demo: demo)
        location = LocationPermission(demo: demo)
        launchAtLogin = LaunchAtLogin()
        updater = Updater()
        settings = SettingsWindowController(monitor: monitor, location: location, launchAtLogin: launchAtLogin, updater: updater)
        statusItem = StatusItemController(monitor: monitor, wifi: wifi, location: location,
                                          launchAtLogin: launchAtLogin, updater: updater) { [weak self] in
            self?.settings.show()
        }
        location.onChange = { [weak self] in
            self?.monitor.refresh()
            self?.wifi.scan()
        }
        SelfCheck.runIfRequested(statusItem: statusItem, settings: settings, monitor: monitor)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Launch arguments used to verify the UI without a person driving the mouse:
///   --self-check <dir>   opens the menu, the hover popover and each Settings tab,
///                        writes PNG snapshots plus a report.txt into <dir>, then quits.
///   --open-menu          opens the menu on launch.
///   --demo               shows fixed sample connections (used for the README screenshots).
///   --expand-networks    with --self-check, expands "Other Networks" before the menu snapshot.
@MainActor
enum SelfCheck {
    static func runIfRequested(statusItem: StatusItemController, settings: SettingsWindowController, monitor: NetworkMonitor) {
        let arguments = CommandLine.arguments
        if arguments.contains("--open-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { statusItem.open() }
        }
        guard let index = arguments.firstIndex(of: "--self-check"), arguments.indices.contains(index + 1) else { return }
        let directory = URL(fileURLWithPath: arguments[index + 1])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var report: [String] = []
        let loginItem = arguments.contains("--test-login-item")

        // Steps run one after another, each followed by a pause for the UI to settle.
        var steps: [(TimeInterval, () -> Void)] = []
        steps.append((2.5, {
            report.append("version=\(AppInfo.version) bundle=\(Bundle.main.bundlePath)")
            report.append("icon=\(monitor.iconKind) name=\(monitor.activeName ?? "-")")
            report.append("ethernet=\(monitor.ethernet.map { "\($0.name) [\($0.interfaceName)] \($0.state.rawValue)" })")
            report.append("wifi=\(monitor.wifi.map { "\($0.name) \($0.state.rawValue)" } ?? "none") power=\(monitor.wifiPowerOn)")
            report.append("status item: \(statusItem.buttonDescription)")
            if arguments.contains("--expand-networks") { statusItem.expandOtherNetworks() }
            statusItem.simulateClick()
        }))
        steps.append((1.0, {
            report.append("menu: \(statusItem.debugDescription_)")
            snapshot(statusItem.panelWindow.contentView, to: directory.appendingPathComponent("menu.png"), backdrop: statusItem.panelWindow)
            statusItem.simulateHover(statusItem.firstHoverableID)
        }))
        steps.append((1.0, {
            report.append("hover: \(statusItem.debugDescription_)")
            // The popover's own chrome is drawn by the window server, so render its content separately.
            if let id = statusItem.shownDetailsID, let connection = monitor.connection(id: id) {
                let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let host = NSHostingView(rootView: DetailsView(connection: connection)
                    .background(Color(white: dark ? 0.16 : 0.93))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .environment(\.colorScheme, dark ? .dark : .light))
                host.frame = NSRect(origin: .zero, size: host.fittingSize)
                let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.backgroundColor = .clear
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                snapshot(host, to: directory.appendingPathComponent("details.png"), backdrop: nil)
            }
            statusItem.simulateHover(nil)
        }))
        steps.append((0.5, {
            report.append("hover ended: \(statusItem.debugDescription_)")
            statusItem.simulateClick()
        }))
        steps.append((0.3, { report.append("menu open after second click: \(statusItem.isOpen)") }))
        for (tab, name) in ["general", "updates", "about"].enumerated() {
            steps.append((1.2, { settings.show(tab: tab) }))
            steps.append((0.2, {
                guard let window = settings.contentWindow else { return }
                report.append("settings \(name): title=\(window.title) size=\(window.frame.size)")
                snapshot(window.contentView?.superview, to: directory.appendingPathComponent("settings-\(name).png"), backdrop: nil)
            }))
        }
        if loginItem {
            let login = LaunchAtLogin()
            let before = login.enabled
            steps.append((1.0, { login.set(true); report.append("login item on: enabled=\(login.enabled) approval=\(login.needsApproval) error=\(login.errorMessage ?? "-")") }))
            steps.append((0.5, { login.set(before); report.append("login item restored: enabled=\(login.enabled) error=\(login.errorMessage ?? "-")") }))
        }
        steps.append((0.2, {
            try? report.joined(separator: "\n").write(to: directory.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }))

        func run(_ index: Int) {
            guard index < steps.count else { return }
            steps[index].1()
            DispatchQueue.main.asyncAfter(deadline: .now() + steps[index].0) { run(index + 1) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { run(0) }
    }

    /// Renders a view hierarchy to a PNG. Vibrancy is composited by the window
    /// server, so menu-style windows get a painted backdrop instead.
    static func snapshot(_ view: NSView?, to url: URL, backdrop: NSWindow?) {
        guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let output = Canvas.bitmap(pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh, pointSize: view.bounds.size) {
            if backdrop != nil {
                let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                NSBezierPath(roundedRect: view.bounds, xRadius: 12, yRadius: 12).fill()
            }
            rep.draw(in: view.bounds)
        }
        try? Canvas.writePNG(output, to: url)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
