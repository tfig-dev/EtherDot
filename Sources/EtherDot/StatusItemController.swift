import AppKit
import SwiftUI
import Combine
import EtherDotCore

/// Borderless panel that can take key focus without activating the app, like a menu.
final class MenuPanel: NSPanel {
    var onCancel: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { onCancel() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case ",": onOpenSettings(); return true
        case "q": NSApp.terminate(nil); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}

/// Owns the menu bar item, the drop-down panel and the hover details popover.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let monitor: NetworkMonitor
    private let wifi: WiFiController
    private let launchAtLogin: LaunchAtLogin
    private let model = MenuModel()
    private let panel: MenuPanel
    private let hosting: NSHostingView<MenuView>
    private let popover = NSPopover()
    private var hoveredID: String?
    private var hoverTimer: Timer?
    private var outsideClickMonitor: Any?
    private var observers: Set<AnyCancellable> = []
    private var lastClose = Date.distantPast

    var isOpen: Bool { panel.isVisible }

    init(monitor: NetworkMonitor, wifi: WiFiController, location: LocationPermission,
         launchAtLogin: LaunchAtLogin, updater: Updater, openSettings: @escaping () -> Void) {
        self.monitor = monitor
        self.wifi = wifi
        self.launchAtLogin = launchAtLogin

        hosting = NSHostingView(rootView: MenuView(monitor: monitor, wifi: wifi, location: location,
                                                   launchAtLogin: launchAtLogin, updater: updater, model: model))
        panel = MenuPanel(contentRect: NSRect(x: 0, y: 0, width: MenuView.width, height: 300),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()

        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
        ])

        panel.contentView = effect
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        panel.onOpenSettings = { [weak self] in self?.close(); openSettings() }

        popover.behavior = .applicationDefined
        popover.animates = false

        model.onClose = { [weak self] in self?.close() }
        model.onOpenSettings = openSettings
        model.onHover = { [weak self] in self?.hoverChanged($0) }
        model.onSizeChange = { [weak self] in self?.resize(to: $0) }

        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)

        monitor.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.updateButton()
                self?.refreshPopover()
            }
            .store(in: &observers)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateButton() }
            .store(in: &observers)
        updateButton()
    }

    // MARK: Menu bar icon

    private static let ethernetImage = RJ45Glyph.templateImage(size: 18)

    private static func symbol(_ name: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular))
        image?.isTemplate = true
        return image
    }

    /// Ethernet always wins over Wi-Fi, exactly like macOS Network Settings.
    func updateButton() {
        guard let button = statusItem.button else { return }
        let defaults = UserDefaults.standard
        let kind = monitor.iconKind
        switch kind {
        case .ethernet: button.image = Self.ethernetImage
        case .wifi: button.image = Self.symbol("wifi", description: "Wi-Fi")
        case .offline: button.image = Self.symbol("wifi.slash", description: "Offline")
        }
        button.appearsDisabled = kind == .offline && defaults.bool(forKey: Pref.dimOfflineIcon)
        let name = monitor.activeName ?? "Offline"
        if defaults.bool(forKey: Pref.showNetworkName) {
            button.title = " " + name
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
        button.toolTip = isOpen ? nil : name
        button.setAccessibilityLabel("EtherDot: \(name)")
    }

    // MARK: Panel

    @objc func toggle() {
        if isOpen {
            close()
        } else if Date().timeIntervalSince(lastClose) > 0.25 {
            open()
        }
    }

    func open() {
        monitor.refresh()
        monitor.setLiveUpdates(true)
        launchAtLogin.refresh()
        wifi.scan()
        hosting.layoutSubtreeIfNeeded()
        resize(to: hosting.fittingSize)
        positionPanel()
        statusItem.button?.highlight(true)
        statusItem.button?.toolTip = nil
        panel.makeKeyAndOrderFront(nil)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.close() }
        }
    }

    func close() {
        guard isOpen else { return }
        hideDetails()
        hoveredID = nil
        monitor.setLiveUpdates(false)
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        lastClose = Date()
        updateButton()
    }

    func windowDidResignKey(_ notification: Notification) {
        // The details popover is a child of the panel; losing key to it is not "clicking away".
        if let key = NSApp.keyWindow, key === popover.contentViewController?.view.window { return }
        close()
    }

    private func positionPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = NSPoint(x: anchor.minX, y: anchor.minY - 5 - panel.frame.height)
        origin.x = max(screen.minX + 8, min(origin.x, screen.maxX - panel.frame.width - 8))
        panel.setFrameOrigin(origin)
    }

    private func resize(to size: CGSize) {
        guard size.height > 0, abs(size.height - panel.frame.height) > 0.5 || abs(size.width - panel.frame.width) > 0.5 else { return }
        let top = panel.frame.maxY
        panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    // MARK: Hover details

    private func hoverChanged(_ id: String?) {
        hoverTimer?.invalidate()
        hoveredID = id
        guard let id else {
            // Brief grace period so moving between rows does not flicker.
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    if self?.hoveredID == nil { self?.hideDetails() }
                }
            }
            return
        }
        guard UserDefaults.standard.bool(forKey: Pref.showHoverDetails) else { return }
        let delay = popover.isShown ? 0.05 : 0.35
        hoverTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                if self?.hoveredID == id { self?.showDetails(for: id) }
            }
        }
    }

    /// Shows the details beside the menu, on whichever side of it has the most room.
    func showDetails(for id: String) {
        guard isOpen, let connection = monitor.connection(id: id) else { return }
        let content = NSHostingController(rootView: DetailsView(connection: connection))
        let size = content.view.fittingSize
        content.preferredContentSize = size
        let screen = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let side = PopoverSide.best(anchor: panel.frame, screen: screen,
                                    popover: CGSize(width: size.width + 24, height: size.height + 24))
        // Left/right anchor to the hovered row; above/below anchor to the whole menu so rows stay visible.
        let row = model.rowFrames[id] ?? hosting.bounds
        let (rect, edge): (NSRect, NSRectEdge)
        switch side {
        case .left: (rect, edge) = (row, .minX)
        case .right: (rect, edge) = (row, .maxX)
        case .below: (rect, edge) = (hosting.bounds, hosting.isFlipped ? .maxY : .minY)
        case .above: (rect, edge) = (hosting.bounds, hosting.isFlipped ? .minY : .maxY)
        }
        if popover.isShown { popover.close() }
        popover.contentViewController = content
        popover.contentSize = size
        popover.show(relativeTo: rect, of: hosting, preferredEdge: edge)
        shownDetailsID = id
        lastPopoverSide = side
    }

    private(set) var shownDetailsID: String?
    private(set) var lastPopoverSide: PopoverSide?

    private func hideDetails() {
        if popover.isShown { popover.close() }
        shownDetailsID = nil
    }

    private func refreshPopover() {
        guard popover.isShown, let id = shownDetailsID,
              let controller = popover.contentViewController as? NSHostingController<DetailsView> else { return }
        guard let connection = monitor.connection(id: id) else {
            hideDetails()
            return
        }
        controller.rootView = DetailsView(connection: connection)
    }

    /// Test hook: frames of the on-screen windows, for the self-check launch arguments.
    var debugDescription_: String {
        let popoverFrame = popover.isShown ? popover.contentViewController?.view.window?.frame : nil
        return "panel=\(panel.frame) popover=\(String(describing: popoverFrame)) side=\(String(describing: lastPopoverSide)) details=\(shownDetailsID ?? "-")"
    }

    /// Test hooks: go through the same paths as a real click on the icon and a real hover.
    func expandOtherNetworks() { model.showOtherNetworks = true }
    func simulateClick() { statusItem.button?.performClick(nil) }
    func simulateHover(_ id: String?) { model.onHover(id) }
    var buttonDescription: String {
        "image=\(statusItem.button?.image?.accessibilityDescription ?? "-") title='\(statusItem.button?.title ?? "")' dimmed=\(statusItem.button?.appearsDisabled ?? false)"
    }

    var firstHoverableID: String? { monitor.activeEthernet?.id ?? monitor.ethernet.first?.id ?? monitor.wifi?.id }
    var panelWindowNumber: Int { panel.windowNumber }
    var popoverWindow: NSWindow? { popover.isShown ? popover.contentViewController?.view.window : nil }
    var panelWindow: NSWindow { panel }
}
