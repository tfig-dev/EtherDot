import AppKit
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
    private var store: SCDynamicStore?
    private var wifiEvents: WiFiEventObserver?
    private var services: [CachedService]?
    private var refreshScheduled = false
    private var liveTimer: Timer?

    /// What rarely changes about a network service. Enumerating services reads the
    /// preferences and the IOKit registry (about 5 ms of CPU), so it is cached and
    /// only rebuilt when the configuration itself changes.
    private struct CachedService {
        let isWiFi: Bool
        let device: String
        let serviceID: String?
        let serviceName: String?
        let hardwareName: String?
        let macAddress: String?
        let interface: SCNetworkInterface
    }

    /// Demo mode shows fixed sample data; it is only used to render the README screenshots.
    private let demo: Bool

    init(demo: Bool = false) {
        self.demo = demo
        if demo {
            loadDemoData()
            return
        }
        startStoreNotifications()
        wifiEvents = WiFiEventObserver { [weak self] in
            Task { @MainActor [weak self] in self?.scheduleRefresh() }
        }
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleRefresh() }
        }
        pathMonitor.start(queue: queue)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.services = nil
                self?.scheduleRefresh()
            }
        }
        // Safety net in case a notification is ever missed: one cheap refresh a minute
        // (cached services, about half a millisecond of CPU).
        let safety = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        safety.tolerance = 15
        RunLoop.main.add(safety, forMode: .common)
        refresh()
    }

    // MARK: Change notifications (no polling)

    /// configd pushes a message whenever a link, an address, the primary route or the
    /// service configuration changes. Between changes the app does not wake up at all.
    private func startStoreNotifications() {
        var context = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                            retain: nil, release: nil, copyDescription: nil)
        let callback: SCDynamicStoreCallBack = { _, changedKeys, info in
            guard let info else { return }
            let monitor = Unmanaged<NetworkMonitor>.fromOpaque(info).takeUnretainedValue()
            let keys = changedKeys as? [String] ?? []
            MainActor.assumeIsolated { monitor.storeChanged(keys) }
        }
        store = SCDynamicStoreCreate(nil, "EtherDot" as CFString, callback, &context)
        guard let store else { return }
        let keys = [
            "State:/Network/Global/IPv4", "State:/Network/Global/IPv6",
            "State:/Network/Interface", "Setup:/Network/Global/IPv4",
        ]
        let patterns = [
            "State:/Network/Interface/[^/]+/Link", "State:/Network/Interface/[^/]+/IPv4",
            "State:/Network/Interface/[^/]+/IPv6", "State:/Network/Service/[^/]+/IPv4",
            "Setup:/Network/Service/[^/]+", "Setup:/Network/Service/[^/]+/Interface",
        ]
        SCDynamicStoreSetNotificationKeys(store, keys as CFArray, patterns as CFArray)
        SCDynamicStoreSetDispatchQueue(store, DispatchQueue.main)
    }

    private func storeChanged(_ keys: [String]) {
        // Adapters added or removed, services renamed or reordered: rebuild the cache.
        if keys.contains(where: { $0.hasPrefix("Setup:") || $0 == "State:/Network/Interface" }) {
            services = nil
        }
        scheduleRefresh()
    }

    /// Coalesces bursts of notifications (plugging a cable fires several) into one refresh.
    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refreshScheduled = false
            self?.refresh()
        }
    }

    /// Signal strength and transmit rate have no change notification, so they are
    /// only polled while the menu is open.
    func setLiveUpdates(_ on: Bool) {
        liveTimer?.invalidate()
        liveTimer = nil
        guard on, !demo else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        liveTimer = timer
    }

    private func loadServices() -> [CachedService] {
        if let services { return services }
        var loaded: [CachedService] = []
        for service in Self.currentServices() where SCNetworkServiceGetEnabled(service) {
            guard let interface = SCNetworkServiceGetInterface(service),
                  let type = SCNetworkInterfaceGetInterfaceType(interface),
                  let device = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            let isWiFi = type == kSCNetworkInterfaceTypeIEEE80211
            guard isWiFi || type == kSCNetworkInterfaceTypeEthernet else { continue }
            loaded.append(CachedService(
                isWiFi: isWiFi,
                device: device,
                serviceID: SCNetworkServiceGetServiceID(service) as String?,
                serviceName: SCNetworkServiceGetName(service) as String?,
                hardwareName: SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?,
                macAddress: SCNetworkInterfaceGetHardwareAddressString(interface) as String?,
                interface: interface
            ))
        }
        services = loaded
        return loaded
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

    /// Set ETHERDOT_TRACE=1 to log every refresh; scripts/perf.sh uses it to count them.
    private static let trace = ProcessInfo.processInfo.environment["ETHERDOT_TRACE"] != nil
    private var refreshCount = 0

    func refresh() {
        guard !demo else { return }
        if Self.trace {
            refreshCount += 1
            FileHandle.standardError.write("refresh \(refreshCount) servicesCached=\(services != nil)\n".data(using: .utf8)!)
        }
        let addresses = Self.interfaceAddresses()
        let primary = (storeValue("State:/Network/Global/IPv4")?["PrimaryInterface"] as? String)
            ?? (storeValue("State:/Network/Global/IPv6")?["PrimaryInterface"] as? String)

        var wired: [ConnectionInfo] = []
        let cached = loadServices()
        let wifiService = cached.first { $0.isWiFi }

        for service in cached where !service.isWiFi {
            let device = service.device
            let linkActive = storeValue("State:/Network/Interface/\(device)/Link")?["Active"] as? Bool ?? false
            guard linkActive else { continue }
            let own = addresses[device] ?? []
            wired.append(ConnectionInfo(
                kind: .ethernet,
                name: ConnectionLabel.ethernet(serviceName: service.serviceName, hardwareName: service.hardwareName, interfaceName: device),
                state: .resolve(linkActive: true, addresses: own),
                interfaceName: device,
                hardwareName: service.hardwareName,
                addresses: own,
                router: router(serviceID: service.serviceID),
                macAddress: service.macAddress,
                speed: Self.mediaSubtype(service.interface),
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
                hardwareName: wifiService?.serviceName,
                addresses: associated ? own : [],
                router: associated ? router(serviceID: wifiService?.serviceID) : nil,
                macAddress: wifiService?.macAddress,
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

/// Forwards CoreWLAN change events (network joined or left, radio switched on or off).
final class WiFiEventObserver: NSObject, CWEventDelegate {
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init()
        let client = CWWiFiClient.shared()
        client.delegate = self
        for event in [CWEventType.ssidDidChange, .powerDidChange, .linkDidChange] {
            try? client.startMonitoringEvent(with: event)
        }
    }

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) { onChange() }
    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) { onChange() }
    func linkDidChangeForWiFiInterface(withName interfaceName: String) { onChange() }
}
