# Performance

EtherDot runs all day in the background, so its idle cost matters more than anything else it does.
The budget is **under 0.1% of one CPU core, with no periodic work while the network is unchanged**.

## Measuring

```bash
./scripts/build-app.sh
./scripts/perf.sh build/EtherDot.app 180
```

The script launches the app, waits for it to settle, then reports CPU time used, average CPU share,
idle wake-ups, memory and the number of refreshes over the interval. Run it with the menu closed and
without touching the network.

## Results

Measured on an Apple silicon Mac running macOS 26, Wi-Fi connected, menu closed.

| | 1.0.0 | 1.0.1 |
| --- | --- | --- |
| CPU time | 0.56 s per 60 s | 0.05 s per 180 s |
| Share of one core | 0.93% | 0.03% |
| Refreshes while idle | one every 3 s | one per minute (safety net) |
| Memory | 18 MB | 17 MB |

## What was wrong in 1.0.0

A 3-second timer rebuilt everything from scratch. Profiling with `sample` showed the time going to
`SCNetworkServiceGetInterface`, called while enumerating the network services through SCPreferences.
That call reads the preferences and the IOKit registry, and its result almost never changes.

Cost of each call the app makes, measured in isolation:

| Call | Own CPU per call | Notes |
| --- | --- | --- |
| Enumerate services (SCPreferences, SCNetworkService) | ~5200 µs | The hot spot |
| List interfaces with media options | ~1270 µs | |
| `getifaddrs` + `getnameinfo` | ~235 µs | |
| CoreWLAN property (`ssid`, `rssiValue`, `security`, …) | 25–225 µs | Each one is also a request to `airportd`; wall time 0.2–1.7 ms |
| `sysctl` `NET_RT_IFLIST2` | ~38 µs | Per-interface byte counters, planned for live traffic |
| `SCDynamicStoreCopyValue` | ~9 µs | |

## Design since 1.0.1

- **Events, not polling.** The app registers notification keys with `configd` (SCDynamicStore) for
  link state, IPv4/IPv6 addresses, the primary route and the service configuration, and with CoreWLAN
  for network, power and link changes. `NWPathMonitor` is a second, independent trigger. Bursts of
  notifications are coalesced into one refresh.
- **Cache what does not change.** Service names, adapter names and MAC addresses are cached and
  rebuilt only when a `Setup:` key or the interface list changes, or after wake from sleep.
- **Poll only what has no event, only while visible.** Wi-Fi signal and transmit rate are read
  every 2 seconds while the menu is open.
- **Safety net.** One refresh a minute using the cache.

### Why not raw system calls everywhere

The saving came from not waking up, not from the API level: a system call made every 3 seconds still
wakes the CPU, while a notification costs nothing until something changes. `configd` already listens
to the kernel's network events and forwards them, and it is the only source for service names. A
`PF_ROUTE` socket would deliver the same kernel events one level lower but without those names.

For live traffic (planned for 1.1) the direct system call is the right tool: `sysctl` with
`NET_RT_IFLIST2` returns the byte counters of every interface in about 38 µs, roughly 0.004% of a
core at one read per second. The app will not use `nettop` or the private NetworkStatistics framework.

## Not yet verified

The change notifications were confirmed to register, but a real network change (plugging a cable,
switching Wi-Fi network, turning Wi-Fi off) could not be triggered during testing without
disconnecting the machine. If a notification were missed, the minute safety refresh would correct
the display within 60 seconds. To check by hand:

```bash
ETHERDOT_TRACE=1 /Applications/EtherDot.app/Contents/MacOS/EtherDot --allow-multiple
```

Each refresh prints a line; plugging or unplugging a cable should print one within a second.
