import SwiftUI
import EtherDotCore

/// View state and callbacks shared between the menu panel and its controller.
@MainActor
final class MenuModel: ObservableObject {
    @Published var showOtherNetworks = false
    /// Row frames in the hosting view's coordinates, used to anchor the details popover.
    var rowFrames: [String: CGRect] = [:]
    var onHover: (String?) -> Void = { _ in }
    var onClose: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onSizeChange: (CGSize) -> Void = { _ in }
}

private struct SizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

struct MenuView: View {
    @ObservedObject var monitor: NetworkMonitor
    @ObservedObject var wifi: WiFiController
    @ObservedObject var location: LocationPermission
    @ObservedObject var launchAtLogin: LaunchAtLogin
    @ObservedObject var updater: Updater
    @ObservedObject var model: MenuModel

    static let width: CGFloat = 296

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ethernetSection
            MenuDivider()
            wifiSection
            MenuDivider()
            MenuActionRow(title: "Network Settings…") { act(SystemSettings.openNetwork) }
            MenuActionRow(title: "Wi-Fi Settings…") { act(SystemSettings.openWiFi) }
            MenuDivider()
            MenuActionRow(title: "Launch at Login", checked: launchAtLogin.enabled) { launchAtLogin.toggle() }
            MenuActionRow(title: "Check for Updates…", enabled: updater.isAvailable) { act(updater.checkForUpdates) }
            MenuActionRow(title: "Settings…", shortcut: "⌘,") { act(model.onOpenSettings) }
            MenuDivider()
            MenuActionRow(title: "Quit EtherDot", shortcut: "⌘Q") { NSApp.terminate(nil) }
        }
        .padding(5)
        .frame(width: Self.width)
        .background(GeometryReader { Color.clear.preference(key: SizeKey.self, value: $0.size) })
        .onPreferenceChange(SizeKey.self) { model.onSizeChange($0) }
    }

    private func act(_ action: @escaping () -> Void) {
        model.onClose()
        action()
    }

    // MARK: Ethernet

    @ViewBuilder private var ethernetSection: some View {
        MenuSectionHeader(title: "Ethernet")
        if monitor.ethernet.isEmpty {
            NetworkRow(icon: .ethernet, title: "Not connected", active: false, muted: true)
        } else {
            ForEach(monitor.ethernet) { connection in
                NetworkRow(icon: .ethernet, title: connection.name,
                           subtitle: connection.isConnected ? nil : connection.state.rawValue,
                           active: connection.isConnected)
                    .reportsHover(id: connection.id, model: model)
            }
        }
    }

    // MARK: Wi-Fi (mirrors the system Wi-Fi menu)

    private var powerBinding: Binding<Bool> {
        Binding(get: { monitor.wifiPowerOn }, set: { newValue in
            wifi.setPower(newValue)
            monitor.refresh()
            if newValue { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { wifi.scan() } }
        })
    }

    private var currentWiFi: ConnectionInfo? {
        guard let current = monitor.wifi, current.state == .connected || current.state == .noAddress else { return nil }
        return current
    }

    @ViewBuilder private var wifiSection: some View {
        HStack {
            Text("Wi-Fi").font(.system(size: 13, weight: .semibold))
            Spacer()
            Toggle("Wi-Fi", isOn: powerBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(monitor.wifi == nil)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)

        if monitor.wifi == nil {
            MenuSectionHeader(title: "No Wi-Fi hardware")
        } else if monitor.wifiPowerOn {
            let current = currentWiFi
            let known = wifi.known.filter { $0.ssid != current?.name }
            if current != nil || !known.isEmpty {
                MenuSectionHeader(title: known.isEmpty ? "Known Network" : "Known Networks")
            }
            if let current {
                NetworkRow(icon: .wifi(level: SignalStrength.level(rssi: current.signal ?? -60)), title: current.name,
                           subtitle: current.isConnected ? nil : current.state.rawValue,
                           active: current.isConnected, secure: (current.security ?? "None") != "None")
                    .reportsHover(id: current.id, model: model)
            }
            ForEach(known) { network in
                networkButton(network)
            }
            if !location.granted {
                MenuActionRow(title: "Show Wi-Fi Network Names…") { act(location.request) }
            } else {
                otherNetworks(excluding: current?.name)
            }
        }
    }

    @ViewBuilder private func otherNetworks(excluding current: String?) -> some View {
        let others = wifi.other.filter { $0.ssid != current }
        HoverHighlight(action: {
            model.showOtherNetworks.toggle()
            if model.showOtherNetworks { wifi.scan() }
        }) {
            HStack {
                Text("Other Networks").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if wifi.scanning { ProgressView().controlSize(.small).scaleEffect(0.7) }
                Image(systemName: model.showOtherNetworks ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
        }
        if model.showOtherNetworks {
            if others.isEmpty {
                MenuSectionHeader(title: wifi.scanning ? "Searching…" : "No other networks found")
            } else if others.count > 7 {
                ScrollView { VStack(spacing: 0) { ForEach(others) { networkButton($0) } } }
                    .frame(height: 7 * NetworkRow.height)
            } else {
                ForEach(others) { networkButton($0) }
            }
        }
    }

    private func networkButton(_ network: WiFiNetwork) -> some View {
        HoverHighlight(action: {
            wifi.join(network) { monitor.refresh() }
        }) {
            NetworkRow(icon: .wifi(level: SignalStrength.level(rssi: network.rssi)), title: network.ssid,
                       active: false, secure: network.secure, busy: wifi.joining == network.ssid, highlightsOnHover: false)
        }
    }
}

// MARK: - Rows

struct MenuDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 9).padding(.vertical, 5)
    }
}

struct MenuSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .frame(height: 20)
    }
}

/// A row that behaves like a native menu item: full-width accent highlight on hover.
struct MenuActionRow: View {
    let title: String
    var shortcut: String?
    var checked = false
    var enabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let highlighted = hovering && enabled
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Spacer(minLength: 8)
                if checked {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                }
                if let shortcut {
                    Text(shortcut).foregroundStyle(highlighted ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.tertiary))
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(highlighted ? AnyShapeStyle(.white) : enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(highlighted ? Color(nsColor: .selectedContentBackgroundColor) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }
}

/// Subtle grey highlight used by the network rows, as in the system Wi-Fi menu.
struct HoverHighlight<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(hovering ? 0.1 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct NetworkRow: View {
    enum Icon { case ethernet, wifi(level: Double) }
    static let height: CGFloat = 30

    let icon: Icon
    let title: String
    var subtitle: String?
    let active: Bool
    var secure = false
    var busy = false
    var muted = false
    var highlightsOnHover = true
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(active ? Color(nsColor: .controlAccentColor) : Color.primary.opacity(0.12))
                glyph.foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                if let subtitle {
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(muted ? .secondary : .primary)
            Spacer(minLength: 6)
            if busy { ProgressView().controlSize(.small).scaleEffect(0.7) }
            if secure {
                Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(hovering && highlightsOnHover && !muted ? 0.1 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var glyph: some View {
        switch icon {
        case .ethernet:
            Image(nsImage: RJ45Glyph.templateImage(size: 16)).renderingMode(.template)
        case .wifi(let level):
            Image(systemName: "wifi", variableValue: active ? 1 : level).font(.system(size: 11, weight: .semibold))
        }
    }
}

private extension View {
    /// Tells the controller when the pointer rests on this row, and where the row is.
    func reportsHover(id: String, model: MenuModel) -> some View {
        background(GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            Color.clear
                .onAppear { model.rowFrames[id] = frame }
                .onChange(of: frame) { model.rowFrames[id] = $0 }
        })
        .onHover { model.onHover($0 ? id : nil) }
    }
}

// MARK: - Details popover

struct DetailsView: View {
    let connection: ConnectionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(connection.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
            Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 4) {
                ForEach(Array(connection.detailRows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(row.label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        if row.label == "IPv6" || row.label == "MAC" {
                            Text(row.value).font(.system(size: 11, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.75)
                        } else {
                            Text(row.value).monospacedDigit().lineLimit(2)
                        }
                    }
                }
            }
            .font(.system(size: 12))
        }
        .padding(12)
        .frame(width: 330, alignment: .leading)
    }
}
