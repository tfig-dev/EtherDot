# Changelog

All notable changes to EtherDot. Versions follow [semantic versioning](https://semver.org).

## 1.0.1

### Fixed
- **Idle CPU use.** 1.0.0 used about 1% of one CPU core permanently while sitting in the menu bar.
  It re-read the whole network configuration every 3 seconds; enumerating the network services
  alone cost about 5 ms of CPU each time, and every cycle also made seven requests to the system
  Wi-Fi daemon (`airportd`). 1.0.1 measures about 0.03%. See [docs/PERFORMANCE.md](docs/PERFORMANCE.md).
- **Two copies could run at once** (for example one from /Applications and one from a build folder
  or the DMG), giving two icons in the menu bar. EtherDot now allows a single instance: a second
  launch asks the running copy to open its menu and quits.

### Changed
- Network monitoring is event-driven instead of polled. The app subscribes to `configd`
  (SCDynamicStore) and CoreWLAN change notifications and does no work between changes.
- The list of network services (names, MAC addresses, adapters) is cached and only rebuilt when
  the configuration changes or the Mac wakes from sleep.
- Wi-Fi signal strength and transmit rate are refreshed every 2 seconds only while the menu is
  open, since macOS offers no change notification for them.
- A safety refresh runs once a minute in case a notification is missed.

### Added
- `scripts/perf.sh`, a repeatable idle-cost measurement (CPU time, wake-ups, memory, refresh count).

## 1.0.0

First release.

- Menu bar icon that shows an RJ45 port when Ethernet is connected and the Wi-Fi icon otherwise.
- Connection labels use the network's name: the SSID for Wi-Fi, the service name for Ethernet.
- Details popover on hover, placed on the side of the menu with the most room.
- Wi-Fi section with on/off switch, known networks and other networks.
- Launch at login, Sparkle updates from GitHub Releases, three-tab Settings window.
- DMG installer, Homebrew cask, CI and release pipeline.
