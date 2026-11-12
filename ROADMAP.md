# Roadmap

## v1.1.0

### Menu
- Remove **Wi-Fi Settings…**, **Launch at Login** and **Check for Updates…** from the menu. They stay
  available only inside the Settings window (General, Updates and About tabs). The Settings window gains
  a Wi-Fi Settings button, since it currently only has Network Settings.

### App icon
- Redraw the icon: move the green dot up relative to the port and make it slightly smaller.
  Regenerate all sizes, the `.icns`, the README icon and the DMG volume icon.

### Features
- **Network adapters:** on launch, detect adapters that can be connected (USB hubs and docks with
  Ethernet ports, USB Wi-Fi dongles) and let the user add them to the app. Detect newly plugged-in
  adapters automatically.
- **Live traffic:** show upload and download speed (for example ↑ 1.2 MB/s ↓ 8.4 MB/s), refreshed every
  second, in the menu and optionally next to the menu bar icon (toggle in Settings).

### Release
- Ship as v1.1.0 through the same pipeline so v1.0.0 users receive it through Check for Updates.
