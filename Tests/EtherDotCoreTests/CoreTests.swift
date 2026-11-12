import Testing
import CoreGraphics
@testable import EtherDotCore

@Suite struct ConnectionStateTests {
    @Test func LinkDownIsDisconnected() {
        #expect(ConnectionState.resolve(linkActive: false, addresses: ["192.168.1.10"]) == .disconnected)
    }

    @Test func LinkWithRoutableAddressIsConnected() {
        #expect(ConnectionState.resolve(linkActive: true, addresses: ["fe80::1", "192.168.1.10"]) == .connected)
        #expect(ConnectionState.resolve(linkActive: true, addresses: ["2001:db8::5"]) == .connected)
    }

    @Test func LinkWithOnlySelfAssignedAddressHasNoAddress() {
        #expect(ConnectionState.resolve(linkActive: true, addresses: ["169.254.10.2", "fe80::1"]) == .noAddress)
        #expect(ConnectionState.resolve(linkActive: true, addresses: []) == .noAddress)
    }
}

@Suite struct MenuBarIconTests {
    @Test func EthernetAlwaysWinsOverWiFi() {
        #expect(MenuBarIconKind.resolve(ethernetConnected: true, wifiConnected: true) == .ethernet)
        #expect(MenuBarIconKind.resolve(ethernetConnected: true, wifiConnected: false) == .ethernet)
    }

    @Test func WiFiOnlyShowsWiFi() {
        #expect(MenuBarIconKind.resolve(ethernetConnected: false, wifiConnected: true) == .wifi)
    }

    @Test func NothingConnectedIsOffline() {
        #expect(MenuBarIconKind.resolve(ethernetConnected: false, wifiConnected: false) == .offline)
    }
}

@Suite struct ConnectionLabelTests {
    @Test func EthernetUsesServiceName() {
        #expect(ConnectionLabel.ethernet(serviceName: "USB 10/100/1000 LAN", hardwareName: "Ethernet", interfaceName: "en7") == "USB 10/100/1000 LAN")
    }

    @Test func EthernetNeverShowsBareType() {
        #expect(ConnectionLabel.ethernet(serviceName: "Ethernet", hardwareName: "Thunderbolt Ethernet Slot 1", interfaceName: "en5") == "Thunderbolt Ethernet Slot 1")
        #expect(ConnectionLabel.ethernet(serviceName: "Ethernet", hardwareName: nil, interfaceName: "en5") == "Ethernet (en5)")
        #expect(ConnectionLabel.ethernet(serviceName: " ", hardwareName: nil, interfaceName: "en5") == "Ethernet (en5)")
    }

    @Test func WiFiUsesSSID() {
        #expect(ConnectionLabel.wifi(ssid: "FIGUEIREDO") == "FIGUEIREDO")
        #expect(ConnectionLabel.wifi(ssid: nil) != "Wi-Fi")
        #expect(ConnectionLabel.wifi(ssid: "") != "Wi-Fi")
    }
}

@Suite struct PopoverSideTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let popover = CGSize(width: 260, height: 220)

    @Test func MenuNearRightEdgeOpensLeft() {
        let menu = CGRect(x: 1100, y: 500, width: 300, height: 370)
        #expect(PopoverSide.best(anchor: menu, screen: screen, popover: popover) == .left)
    }

    @Test func MenuNearLeftEdgeOpensRight() {
        let menu = CGRect(x: 20, y: 500, width: 300, height: 370)
        #expect(PopoverSide.best(anchor: menu, screen: screen, popover: popover) == .right)
    }

    @Test func NarrowScreenFallsBackToBelow() {
        let narrow = CGRect(x: 0, y: 0, width: 420, height: 900)
        let menu = CGRect(x: 60, y: 560, width: 300, height: 310)
        #expect(PopoverSide.best(anchor: menu, screen: narrow, popover: popover) == .below)
    }

    @Test func PrefersSideThatFitsOverRoomierSideThatDoesNot() {
        let tiny = CGRect(x: 0, y: 0, width: 800, height: 300)
        let menu = CGRect(x: 280, y: 100, width: 300, height: 180)
        // Below has only 100 pt and above 20 pt; left (280) is the roomiest side that fits 260.
        #expect(PopoverSide.best(anchor: menu, screen: tiny, popover: popover) == .left)
    }
}

@Suite struct DetailRowTests {
    @Test func DetailRowsListAddressesAndHideLinkLocalIPv6() {
        let info = ConnectionInfo(kind: .ethernet, name: "USB 10/100/1000 LAN", state: .connected, interfaceName: "en7",
                                  addresses: ["192.168.1.20", "fe80::1c2f", "2001:db8::20"], router: "192.168.1.1",
                                  speed: "1000baseT", isPrimary: true)
        let rows = info.detailRows
        #expect(rows.first == DetailRow("Status", "Connected"))
        #expect(rows.contains(DetailRow("IPv4", "192.168.1.20")))
        #expect(rows.contains(DetailRow("IPv6", "2001:db8::20")))
        #expect(!rows.contains { $0.value == "fe80::1c2f" })
        #expect(rows.contains(DetailRow("Router", "192.168.1.1")))
        #expect(rows.contains(DetailRow("Route", "Primary connection")))
    }

    @Test func SignalLevelIsMonotonic() {
        #expect(SignalStrength.level(rssi: -50) > SignalStrength.level(rssi: -70))
        #expect(SignalStrength.level(rssi: -70) > SignalStrength.level(rssi: -90))
    }
}
