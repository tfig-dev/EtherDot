# Changelog

All notable changes to EtherDot. Versions follow [semantic versioning](https://semver.org).

## 1.1.0

### Changed
- **Shorter menu.** Wi-Fi Settings…, Launch at Login and Check for Updates… are no longer in the
  menu. Launch at login is in Settings › General; Check for Updates is in Settings › Updates and About.
- **New app icon.** The green link LED now sits in front of the plug instead of behind it, and is
  smaller (radius 92 instead of 112 on the 1024 grid).
- **Stable code signature.** Releases are signed with a self-signed certificate instead of an ad-hoc
  signature. An ad-hoc signature is a hash of the binary, so every release looked like a new app to
  macOS, which then asked for Location permission again. macOS asks one last time when updating to
  1.1.0, then keeps the permission across updates.
- **Debug tools out of release builds.** The demo data and the self-check (used for screenshots and
  UI checks) are compiled only into debug builds (`scripts/self-check.sh`).

### Fixed
- In demo mode the Wi-Fi switch and the network list acted on the real Wi-Fi. Demo mode no longer
  touches the network (debug builds only).

### Removed
- Unused code: two test accessors (`panelWindowNumber`, `popoverWindow`) and the unused
  `--open-menu` launch option.

### Added
- **Performance budget in CI.** Every push, pull request and release runs the app idle for two
  minutes and fails if it uses more than 0.1% of a CPU core or refreshes more than twice a minute
  (`scripts/perf.sh`).
- README image of the two menu bar icons in light and dark menu bars.

### Verified
- Ethernet detection and the switch to the RJ45 icon, on real hardware.

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
