import AppKit
import Combine
import CoreWLAN
import CoreLocation
import EtherDotCore

struct WiFiNetwork: Identifiable, Equatable {
    var id: String { ssid }
    let ssid: String
    let rssi: Int
    let secure: Bool
    let known: Bool
}

/// Scans for networks, joins them and switches the Wi-Fi radio, like the system Wi-Fi menu.
@MainActor
final class WiFiController: ObservableObject {
    @Published private(set) var known: [WiFiNetwork] = []
    @Published private(set) var other: [WiFiNetwork] = []
    @Published private(set) var scanning = false
    @Published private(set) var joining: String?

    private var scanned: [String: CWNetwork] = [:]
    private let queue = DispatchQueue(label: "EtherDot.WiFiScan", qos: .userInitiated)

    private let demo: Bool

    init(demo: Bool = false) {
        self.demo = demo
        if demo {
            known = [WiFiNetwork(ssid: "Office", rssi: -61, secure: true, known: true)]
            other = [("Cafe Guest", -70, false), ("Library", -78, true), ("Neighbour 5G", -83, true)]
                .map { WiFiNetwork(ssid: $0.0, rssi: $0.1, secure: $0.2, known: false) }
        }
    }

    func scan() {
        guard !demo else { return }
        guard !scanning, let interface = CWWiFiClient.shared().interface(), interface.powerOn() else {
            if CWWiFiClient.shared().interface()?.powerOn() != true { known = []; other = [] }
            return
        }
        scanning = true
        queue.async {
            let found = (try? interface.scanForNetworks(withSSID: nil)) ?? interface.cachedScanResults() ?? []
            let profiles = interface.configuration()?.networkProfiles.array as? [CWNetworkProfile] ?? []
            let knownNames = Set(profiles.compactMap(\.ssid))
            // One entry per SSID, keeping the strongest access point.
            var strongest: [String: CWNetwork] = [:]
            for network in found {
                guard let ssid = network.ssid, !ssid.isEmpty else { continue }
                if let existing = strongest[ssid], existing.rssiValue >= network.rssiValue { continue }
                strongest[ssid] = network
            }
            let networks = strongest.map { ssid, network in
                WiFiNetwork(ssid: ssid, rssi: network.rssiValue, secure: !network.supportsSecurity(.none), known: knownNames.contains(ssid))
            }
            DispatchQueue.main.async {
                self.scanned = strongest
                self.known = networks.filter(\.known).sorted { $0.rssi > $1.rssi }
                self.other = networks.filter { !$0.known }.sorted { $0.ssid.localizedCaseInsensitiveCompare($1.ssid) == .orderedAscending }
                self.scanning = false
            }
        }
    }

    func setPower(_ on: Bool) {
        do {
            try CWWiFiClient.shared().interface()?.setPower(on)
        } catch {
            SystemSettings.openWiFi()
        }
    }

    /// Joins open networks and networks whose password is already in the keychain.
    /// Anything that needs a password typed is handed to Wi-Fi Settings.
    func join(_ network: WiFiNetwork, completion: @escaping () -> Void) {
        guard let target = scanned[network.ssid], let interface = CWWiFiClient.shared().interface() else {
            SystemSettings.openWiFi()
            return
        }
        guard network.known || !network.secure else {
            SystemSettings.openWiFi()
            return
        }
        joining = network.ssid
        queue.async {
            var failed = false
            do {
                try interface.associate(to: target, password: nil)
            } catch {
                failed = true
            }
            DispatchQueue.main.async {
                self.joining = nil
                if failed { SystemSettings.openWiFi() }
                completion()
            }
        }
    }
}

/// macOS only tells apps the Wi-Fi network name once they have Location permission.
@MainActor
final class LocationPermission: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus
    private let manager = CLLocationManager()
    var onChange: (() -> Void)?

    private let demo: Bool

    init(demo: Bool = false) {
        self.demo = demo
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var granted: Bool { demo || status == .authorizedAlways || status == .authorized }
    var canAsk: Bool { status == .notDetermined }

    func request() {
        if canAsk {
            NSApp.activate(ignoringOtherApps: true)
            manager.requestWhenInUseAuthorization()
        } else {
            SystemSettings.openLocationPrivacy()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        Task { @MainActor in
            self.status = newStatus
            self.onChange?()
        }
    }
}

@MainActor
enum SystemSettings {
    static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    static func openNetwork() { open("x-apple.systempreferences:com.apple.Network-Settings.extension") }
    static func openWiFi() { open("x-apple.systempreferences:com.apple.wifi-settings-extension") }
    static func openLocationPrivacy() { open("x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") }
    static func openLoginItems() { open("x-apple.systempreferences:com.apple.LoginItems-Settings.extension") }
}
