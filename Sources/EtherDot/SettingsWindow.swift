import AppKit
import SwiftUI
import EtherDotCore

/// Preferences window with tabs in the top toolbar: General, Updates, About.
@MainActor
final class SettingsWindowController: NSObject {
    private var window: NSWindow?
    private var tabs: SettingsTabController?
    private let monitor: NetworkMonitor
    private let location: LocationPermission
    private let launchAtLogin: LaunchAtLogin
    private let updater: Updater

    init(monitor: NetworkMonitor, location: LocationPermission, launchAtLogin: LaunchAtLogin, updater: Updater) {
        self.monitor = monitor
        self.location = location
        self.launchAtLogin = launchAtLogin
        self.updater = updater
    }

    var contentWindow: NSWindow? { window }

    func show(tab: Int? = nil) {
        if window == nil {
            let tabs = SettingsTabController()
            tabs.tabStyle = .toolbar
            tabs.add(title: "General", symbol: "gearshape",
                     view: GeneralSettings(location: location, launchAtLogin: launchAtLogin))
            tabs.add(title: "Updates", symbol: "arrow.triangle.2.circlepath", view: UpdateSettings(updater: updater))
            tabs.add(title: "About", symbol: "info.circle", view: AboutSettings(updater: updater))

            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
            self.tabs = tabs
            tabs.fitWindow(animated: false)
        }
        if let tab, let tabs, tabs.tabViewItems.indices.contains(tab) {
            tabs.selectedTabViewItemIndex = tab
        }
        launchAtLogin.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class SettingsTabController: NSTabViewController {
    func add<Content: View>(title: String, symbol: String, view: Content) {
        let controller = NSHostingController(rootView: view)
        controller.title = title
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        addTabViewItem(item)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindow(animated: true)
    }

    /// Resizes the window to the selected pane, keeping the title bar in place.
    func fitWindow(animated: Bool) {
        guard let window = view.window, tabViewItems.indices.contains(selectedTabViewItemIndex),
              let pane = tabViewItems[selectedTabViewItemIndex].viewController else { return }
        let size = pane.view.fittingSize
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        let origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(NSRect(origin: origin, size: frame.size), display: true, animate: animated && window.isVisible)
    }
}

// MARK: - Layout helpers (right-aligned labels, controls on the right)

private struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 14) {
            content()
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 24)
        .frame(width: 500, alignment: .center)
    }
}

private struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        GridRow {
            Text(label.isEmpty ? "" : label + ":")
                .gridColumnAlignment(.trailing)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @ObservedObject var location: LocationPermission
    @ObservedObject var launchAtLogin: LaunchAtLogin
    @AppStorage(Pref.showNetworkName) private var showNetworkName = false
    @AppStorage(Pref.dimOfflineIcon) private var dimOfflineIcon = true
    @AppStorage(Pref.showHoverDetails) private var showHoverDetails = true

    var body: some View {
        SettingsPane {
            SettingsRow(label: "Startup") {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin.enabled }, set: { launchAtLogin.set($0) }))
                if launchAtLogin.needsApproval {
                    Caption("Waiting for approval in System Settings › General › Login Items.")
                }
                if let message = launchAtLogin.errorMessage {
                    Caption("Couldn't change the login item: \(message)")
                }
            }
            SettingsRow(label: "Menu bar") {
                Toggle("Show network name next to the icon", isOn: $showNetworkName)
                Toggle("Dim the icon when offline", isOn: $dimOfflineIcon)
                Caption("The icon shows Ethernet whenever a cable is connected, and Wi-Fi otherwise.")
            }
            SettingsRow(label: "Details") {
                Toggle("Show connection details on hover", isOn: $showHoverDetails)
            }
            SettingsRow(label: "Wi-Fi names") {
                if location.granted {
                    Label("Location access allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Button(location.canAsk ? "Allow Location Access…" : "Open Location Settings…") { location.request() }
                }
                Caption("macOS only reveals Wi-Fi network names to apps with Location permission. EtherDot never reads or stores your location.")
            }
            SettingsRow(label: "System") {
                Button("Open Network Settings…") { SystemSettings.openNetwork() }
            }
        }
    }
}

// MARK: - Updates

struct UpdateSettings: View {
    @ObservedObject var updater: Updater

    private var lastChecked: String {
        guard let date = updater.lastCheck else { return "Never" }
        return date.formatted(.relative(presentation: .named)) + " (" + date.formatted(date: .abbreviated, time: .shortened) + ")"
    }

    var body: some View {
        SettingsPane {
            SettingsRow(label: "Updates") {
                Toggle("Check for updates automatically",
                       isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.automaticallyChecks = $0 }))
                Toggle("Download and install updates automatically",
                       isOn: Binding(get: { updater.automaticallyDownloads }, set: { updater.automaticallyDownloads = $0 }))
                    .disabled(!updater.automaticallyChecks)
            }
            .disabled(!updater.isAvailable)
            SettingsRow(label: "Last checked") {
                Text(lastChecked)
            }
            SettingsRow(label: "") {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.isAvailable || !updater.canCheck)
                Caption(updater.isAvailable
                        ? "Updates are downloaded from the EtherDot releases on GitHub and verified before they are installed."
                        : "Updates are unavailable in development builds.")
            }
        }
    }
}

// MARK: - About

struct AboutSettings: View {
    @ObservedObject var updater: Updater

    private var icon: NSImage {
        if Bundle.main.bundleIdentifier != nil, let image = NSImage(named: NSImage.applicationIconName) { return image }
        return AppIconArtwork.image(pixels: 256)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .accessibilityLabel("EtherDot icon")
            VStack(alignment: .leading, spacing: 5) {
                Text(AppInfo.name).font(.system(size: 24, weight: .semibold))
                Text("Version \(AppInfo.version)").foregroundStyle(.secondary)
                Text("By \(AppInfo.author)").foregroundStyle(.secondary)
                Link(AppInfo.repositoryURL.absoluteString.replacingOccurrences(of: "https://", with: ""),
                     destination: AppInfo.repositoryURL)
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.isAvailable || !updater.canCheck)
                    .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 30)
        .frame(width: 500)
    }
}
