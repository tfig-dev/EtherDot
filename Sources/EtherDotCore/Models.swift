import Foundation
import CoreGraphics

public enum ConnectionState: String, Equatable, Sendable {
    case connected = "Connected"
    case noAddress = "No IP address"
    case disconnected = "Not connected"
    case off = "Off"

    /// A link with a routable address is connected; a live link that only has
    /// self-assigned or link-local addresses is still waiting for one.
    public static func resolve(linkActive: Bool, addresses: [String]) -> ConnectionState {
        guard linkActive else { return .disconnected }
        return addresses.contains(where: IPAddress.isRoutable) ? .connected : .noAddress
    }
}

public enum IPAddress {
    public static func isIPv6(_ address: String) -> Bool { address.contains(":") }

    public static func isRoutable(_ address: String) -> Bool {
        let lower = address.lowercased()
        if isIPv6(lower) {
            return !(lower.hasPrefix("fe80") || lower == "::1")
        }
        return !(lower.hasPrefix("169.254.") || lower.hasPrefix("127.") || lower == "0.0.0.0")
    }
}

/// Which glyph the menu bar shows. Same priority as macOS: wired beats wireless.
public enum MenuBarIconKind: Equatable, Sendable {
    case ethernet, wifi, offline

    public static func resolve(ethernetConnected: Bool, wifiConnected: Bool) -> MenuBarIconKind {
        if ethernetConnected { return .ethernet }
        if wifiConnected { return .wifi }
        return .offline
    }
}

public struct DetailRow: Equatable, Sendable {
    public let label: String
    public let value: String
    public init(_ label: String, _ value: String) { self.label = label; self.value = value }
}

public struct ConnectionInfo: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable { case ethernet, wifi }

    public var id: String { interfaceName }
    public var kind: Kind
    /// What the user sees: the network service name for Ethernet, the SSID for Wi-Fi.
    public var name: String
    public var state: ConnectionState
    public var interfaceName: String
    public var hardwareName: String?
    public var addresses: [String]
    public var router: String?
    public var macAddress: String?
    public var speed: String?
    public var isPrimary: Bool
    public var signal: Int?
    public var channel: String?
    public var security: String?
    public var transmitRate: Double?

    public init(kind: Kind, name: String, state: ConnectionState, interfaceName: String, hardwareName: String? = nil,
                addresses: [String] = [], router: String? = nil, macAddress: String? = nil, speed: String? = nil,
                isPrimary: Bool = false, signal: Int? = nil, channel: String? = nil, security: String? = nil,
                transmitRate: Double? = nil) {
        self.kind = kind; self.name = name; self.state = state; self.interfaceName = interfaceName
        self.hardwareName = hardwareName; self.addresses = addresses; self.router = router
        self.macAddress = macAddress; self.speed = speed; self.isPrimary = isPrimary
        self.signal = signal; self.channel = channel; self.security = security; self.transmitRate = transmitRate
    }

    public var isConnected: Bool { state == .connected }

    public var detailRows: [DetailRow] {
        var rows = [DetailRow("Status", state.rawValue)]
        if isPrimary { rows.append(DetailRow("Route", "Primary connection")) }
        if let hardwareName, hardwareName != name {
            rows.append(DetailRow("Adapter", hardwareName))
        }
        rows.append(DetailRow("Interface", interfaceName))
        for address in addresses where !IPAddress.isIPv6(address) {
            rows.append(DetailRow("IPv4", address))
        }
        if let router { rows.append(DetailRow("Router", router)) }
        for address in addresses where IPAddress.isIPv6(address) && IPAddress.isRoutable(address) {
            rows.append(DetailRow("IPv6", address))
        }
        if let speed { rows.append(DetailRow("Speed", speed)) }
        if let signal { rows.append(DetailRow("Signal", "\(signal) dBm")) }
        if let channel { rows.append(DetailRow("Channel", channel)) }
        if let security { rows.append(DetailRow("Security", security)) }
        if let transmitRate, transmitRate > 0 { rows.append(DetailRow("Tx rate", "\(Int(transmitRate)) Mbps")) }
        if let macAddress { rows.append(DetailRow("MAC", macAddress)) }
        return rows
    }
}

public enum ConnectionLabel {
    public static let hiddenWiFiName = "Wi-Fi network"

    /// The network service name ("USB 10/100/1000 LAN"), never the bare connection type.
    public static func ethernet(serviceName: String?, hardwareName: String?, interfaceName: String) -> String {
        for candidate in [serviceName, hardwareName] {
            if let value = candidate?.trimmingCharacters(in: .whitespaces), !value.isEmpty, value.lowercased() != "ethernet" {
                return value
            }
        }
        return "Ethernet (\(interfaceName))"
    }

    public static func wifi(ssid: String?) -> String {
        if let ssid, !ssid.isEmpty { return ssid }
        return hiddenWiFiName
    }
}

public enum PopoverSide: Equatable, Sendable, CaseIterable {
    case left, right, below, above

    /// Picks the side of `anchor` with the most free screen space, preferring
    /// sides the popover actually fits on. Rects use AppKit's bottom-left origin.
    public static func best(anchor: CGRect, screen: CGRect, popover: CGSize) -> PopoverSide {
        let options: [(side: PopoverSide, room: CGFloat, needed: CGFloat)] = [
            (.left, anchor.minX - screen.minX, popover.width),
            (.right, screen.maxX - anchor.maxX, popover.width),
            (.below, anchor.minY - screen.minY, popover.height),
            (.above, screen.maxY - anchor.maxY, popover.height),
        ]
        let sorted = options.sorted { $0.room > $1.room }
        return (sorted.first { $0.room >= $0.needed } ?? sorted[0]).side
    }
}

public enum SignalStrength {
    /// Maps RSSI in dBm to 0...1 for the Wi-Fi bars.
    public static func level(rssi: Int) -> Double {
        switch rssi {
        case (-55)...: return 1
        case (-67)...: return 0.67
        case (-80)...: return 0.34
        default: return 0.1
        }
    }
}
