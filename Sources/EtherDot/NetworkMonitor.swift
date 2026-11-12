import Foundation
import Combine
import Network
import SystemConfiguration
import CoreWLAN
import Darwin
import EtherDotCore

/// Watches the Mac's Ethernet services and Wi-Fi interface.
@MainActor
final class NetworkMonitor: ObservableObject {
    /// Ethernet services whose link is up, connected ones first.
    @Published private(set) var ethernet: [ConnectionInfo] = []
    /// The Wi-Fi interface, or nil when the Mac has none.
    @Published private(set) var wifi: ConnectionInfo?
    @Published private(set) var wifiPowerOn = false

    var activeEthernet: ConnectionInfo? { ethernet.first { $0.isConnected } }
    var wifiConnected: Bool { wifi?.isConnected == true }

    var iconKind: MenuBarIconKind {
        .resolve(ethernetConnected: activeEthernet != nil, wifiConnected: wifiConnected)
    }

    /// Name of the connection the menu bar icon represents.
    var activeName: String? {
        switch iconKind {
        case .ethernet: return activeEthernet?.name
        case .wifi: return wifi?.name
        case .offline: return nil
        }
    }

    func connection(id: String) -> ConnectionInfo? {
        if wifi?.id == id { return wifi }
        return ethernet.first { $0.id == id }
    }

    private let pathMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "EtherDot.NetworkMonitor")
    private let store = SCDynamicStoreCreate(nil, "EtherDot" as CFString, nil, nil)
    private var timer: Timer?

    /// Demo mode shows fixed sample data; it is only used to render the README screenshots.
    private let demo: Bool

    init(demo: Bool = false) {
        self.demo = demo
        if demo {
            loadDemoData()
            return
        }
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        pathMonitor.start(queue: queue)
        refresh()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func loadDemoData() {
        ethernet = [ConnectionInfo(kind: .ethernet, name: "USB 10/100/1000 LAN", state: .connected, interfaceName: "en7",
                                   addresses: ["192.168.1.24", "2001:db8:1f:7d00:1c2a:46cf:88c4:8afa"], router: "192.168.1.1",
                                   macAddress: "00:e0:4c:68:01:2a", speed: "1000baseT", isPrimary: true)]
        wifi = ConnectionInfo(kind: .wifi, name: "Home Network", state: .connected, interfaceName: "en0", hardwareName: "Wi-Fi",
                              addresses: ["192.168.1.87"], router: "192.168.1.1", macAddress: "a0:78:17:00:00:01",
                              signal: -52, channel: "44 (5 GHz)", security: "WPA3 Personal", transmitRate: 866)
        wifiPowerOn = true
    }

    func refresh() {
        guard !demo else { return }
        let addresses = Self.interfaceAddresses()
        let primary = (storeValue("State:/Network/Global/IPv4")?["PrimaryInterface"] as? String)
            ?? (storeValue("State:/Network/Global/IPv6")?["PrimaryInterface"] as? String)

        var wired: [ConnectionInfo] = []
        var wifiService: (name: String?, id: String?, interface: SCNetworkInterface)?

        for service in Self.currentServices() where SCNetworkServiceGetEnabled(service) {
            guard let interface = SCNetworkServiceGetInterface(service),
                  let type = SCNetworkInterfaceGetInterfaceType(interface),
                  let device = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            let serviceID = SCNetworkServiceGetServiceID(service) as String?
            let serviceName = SCNetworkServiceGetName(service) as String?

            if type == kSCNetworkInterfaceTypeIEEE80211 {
                wifiService = (serviceName, serviceID, interface)
                continue
            }
            guard type == kSCNetworkInterfaceTypeEthernet else { continue }
            let linkActive = storeValue("State:/Network/Interface/\(device)/Link")?["Active"] as? Bool ?? false
            guard linkActive else { continue }

            let hardware = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
            let own = addresses[device] ?? []
            wired.append(ConnectionInfo(
                kind: .ethernet,
                name: ConnectionLabel.ethernet(serviceName: serviceName, hardwareName: hardware, interfaceName: device),
                state: .resolve(linkActive: true, addresses: own),
                interfaceName: device,
                hardwareName: hardware,
                addresses: own,
                router: router(serviceID: serviceID),
                macAddress: SCNetworkInterfaceGetHardwareAddressString(interface) as String?,
                speed: Self.mediaSubtype(interface),
                isPrimary: device == primary
            ))
        }
        wired.sort { ($0.isPrimary ? 0 : 1, $0.isConnected ? 0 : 1, $0.interfaceName) < ($1.isPrimary ? 0 : 1, $1.isConnected ? 0 : 1, $1.interfaceName) }

        var wireless: ConnectionInfo?
        var power = false
        if let client = CWWiFiClient.shared().interface(), let device = client.interfaceName {
            power = client.powerOn()
            let own = addresses[device] ?? []
            let linkActive = storeValue("State:/Network/Interface/\(device)/Link")?["Active"] as? Bool ?? false
            let state: ConnectionState = power ? .resolve(linkActive: linkActive, addresses: own) : .off
            let associated = state != .off && state != .disconnected
            wireless = ConnectionInfo(
                kind: .wifi,
                name: ConnectionLabel.wifi(ssid: client.ssid()),
                state: state,
                interfaceName: device,
                hardwareName: wifiService?.name,
                addresses: associated ? own : [],
                router: associated ? router(serviceID: wifiService?.id) : nil,
                macAddress: client.hardwareAddress(),
                isPrimary: device == primary,
                signal: associated ? client.rssiValue() : nil,
                channel: associated ? Self.describe(client.wlanChannel()) : nil,
                security: associated ? Self.describe(client.security()) : nil,
                transmitRate: associated ? client.transmitRate() : nil
            )
        }

        if ethernet != wired { ethernet = wired }
        if wifi != wireless { wifi = wireless }
        if wifiPowerOn != power { wifiPowerOn = power }
    }

    private func storeValue(_ key: String) -> [String: Any]? {
        SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
    }

    private func router(serviceID: String?) -> String? {
        guard let serviceID else { return nil }
        return storeValue("State:/Network/Service/\(serviceID)/IPv4")?["Router"] as? String
    }

    private static func currentServices() -> [SCNetworkService] {
        guard let preferences = SCPreferencesCreate(nil, "EtherDot" as CFString, nil),
              let set = SCNetworkSetCopyCurrent(preferences),
              let services = SCNetworkSetCopyServices(set) as? [SCNetworkService] else { return [] }
        return services
    }

    /// The negotiated media, e.g. "1000baseT".
    private static func mediaSubtype(_ interface: SCNetworkInterface) -> String? {
        var current: Unmanaged<CFDictionary>?
        var active: Unmanaged<CFDictionary>?
        guard SCNetworkInterfaceCopyMediaOptions(interface, &current, &active, nil, false) else { return nil }
        let currentOptions = current?.takeRetainedValue() as? [String: Any]
        let activeOptions = active?.takeRetainedValue() as? [String: Any]
        let key = kSCPropNetEthernetMediaSubType as String
        let subtype = (activeOptions?[key] as? String) ?? (currentOptions?[key] as? String)
        return subtype == "autoselect" ? nil : subtype
    }

    private static func describe(_ channel: CWChannel?) -> String? {
        guard let channel else { return nil }
        let band: String
        switch channel.channelBand {
        case .band2GHz: band = "2.4 GHz"
        case .band5GHz: band = "5 GHz"
        case .band6GHz: band = "6 GHz"
        default: band = ""
        }
        return band.isEmpty ? "\(channel.channelNumber)" : "\(channel.channelNumber) (\(band))"
    }

    static func describe(_ security: CWSecurity) -> String? {
        switch security {
        case .none: return "None"
        case .WEP: return "WEP"
        case .wpaPersonal, .wpaPersonalMixed: return "WPA Personal"
        case .wpa2Personal: return "WPA2 Personal"
        case .personal: return "WPA/WPA2 Personal"
        case .wpa3Personal: return "WPA3 Personal"
        case .wpa3Transition: return "WPA2/WPA3 Personal"
        case .dynamicWEP, .wpaEnterprise, .wpaEnterpriseMixed, .wpa2Enterprise, .enterprise, .wpa3Enterprise: return "Enterprise"
        case .OWE, .oweTransition: return "Enhanced Open"
        default: return nil
        }
    }

    static func interfaceAddresses() -> [String: [String]] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return [:] }
        defer { freeifaddrs(first) }
        var result: [String: [String]] = [:]
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) || address.pointee.sa_family == UInt8(AF_INET6) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            // Drop the "%en0" scope suffix from link-local IPv6 addresses.
            let text = String(cString: host).split(separator: "%").first.map(String.init) ?? ""
            result[name, default: []].append(text)
        }
        return result.mapValues { Array(Set($0)).sorted() }
    }
}
