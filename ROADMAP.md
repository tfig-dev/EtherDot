# Roadmap

Shipped work is listed in [CHANGELOG.md](CHANGELOG.md).

## Next (planned as 1.2.0)

- **Network adapters:** on launch, detect adapters that can be connected (USB hubs and docks with
  Ethernet ports, USB Wi-Fi dongles) and let the user add them to the app. Detect newly plugged-in
  adapters automatically.
- **Live traffic:** show upload and download speed (for example ↑ 1.2 MB/s ↓ 8.4 MB/s), refreshed every
  second, in the menu and optionally next to the menu bar icon (toggle in Settings). Read the byte
  counters with `sysctl` `NET_RT_IFLIST2` (see docs/PERFORMANCE.md), and only while they are visible.
- Ship through the same pipeline so earlier versions receive it through Check for Updates.
