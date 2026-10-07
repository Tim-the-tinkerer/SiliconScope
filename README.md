# Silicon Scope

**Version 1.1.7** — a native macOS monitor for Apple Silicon CPU, GPU, unified memory, and the Apple Neural Engine.

See [CHANGELOG.md](CHANGELOG.md) for release history.

## What it does

Silicon Scope is a live telemetry console for the chip in your Mac. It samples the same private **IOReport** energy model that `powermetrics` uses, and the PMP energy histograms when a chip’s Energy Model CPU counter stays at zero, so it can show CPU / GPU / Neural Engine **watts** and cluster residency **without sudo**.

The window has these pages:

| Page | Contents |
|------|----------|
| Overview | Four live gauges with history charts, stacked package power, memory mix, and basic temperature, network, and disk readings |
| CPU | Cluster residency (E, P, or S), frequency, per-core bars, power and temperature |
| GPU | Active and frequency-scaled residency, DVFS frequency, GPU power |
| Memory | Used / app / wired / compressed / cached / free, swap, pressure history |
| Neural Engine | Energy-model watts (measured) and estimated activity — not occupancy (ANE is idle until a model runs) |
| Power | Stacked CPU + GPU + ANE watts plus DRAM / GPU SRAM |
| Temperatures | HID sensors and SMC keys, grouped into CPU, GPU, and other |
| Network | Download and upload rates, a three-minute chart, and each active interface. The total is Wi-Fi and Ethernet. A VPN is listed and counted only when those links are down |
| Disk | Internal, external, and network drives, with free space and the volumes mounted on each. Click a drive for storage details and SMART data when the drive reports it |
| Processes | Highest CPU consumers by default. Search by name or PID. Column headers sort by name, PID, CPU, memory, or threads. Name and memory keep that order instead of jumping back to CPU. Click a row for path, owner, parent, CPU time, and memory. Right-click to copy, reveal in Finder, quit, or force quit (sampled only while this page is open) |
| Hardware | Chip identity, core counts, DVFS tables, telemetry mode and per-metric confidence |

History charts keep the last **three minutes**, regardless of the 0.5 / 1 / 2 s sample interval.

## Requirements

- macOS 13 or later
- Apple Silicon for GPU / ANE energy and cluster frequency (Intel Macs still show CPU and memory)
- Xcode Command Line Tools / Swift toolchain (to build)
- For `swift test`: Xcode (set `DEVELOPER_DIR` if needed)

## Build & run

```bash
cd ~/Apps-Usefull/SiliconScope
chmod +x build-app.sh
./build-app.sh
```

This compiles a **1.1.7** release binary, packages `SiliconScope.app`, ad-hoc codesigns it, and launches it.

Build without launching:

```bash
./build-app.sh --no-launch
```

Or run the binary directly during development:

```bash
swift run
swift run SiliconScope --sample
```

`--sample` prints one reading, including CPU and GPU temperature. `--self-test` checks formatters and metric math without opening a window.

Regenerate the app icon (optional):

```bash
swift Scripts/GenerateAppIcon.swift
```

## Tests

```bash
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift test
```

Unit tests cover energy-to-watts conversion, frequency residency math, M1 and M4 DVFS ladder selection, power-histogram normalization, DVFS unit decoding, cluster letters, ANE activity estimates, telemetry confidence, time-windowed history, formatters, channel parsing, SMC temperature names, and that repeated samples do not accumulate memory.

## Usage

1. Open **Silicon Scope**.
2. Watch the overview tiles, or press **⌘1–⌘9** to jump to the first nine pages.
3. **Silicon Scope → Settings…** (⌘,) for polling interval, open at login, open window at launch, and the menu bar extra. The sidebar interval picker and gear also open those controls. **⌘P** pauses sampling.
4. A menu bar extra shows `CPU 42% 36° GPU 32% 30° MEM 60% ANE ~0%`. The CPU temperature is the average of the performance-cluster and efficiency-cluster readings. The GPU temperature is the average of the GPU sensors. On chips without the HID cluster diodes, those averages come from the SMC performance, efficiency, and GPU keys. Click the extra for a key to those names, plus watts, or **Settings…**. Toggle with **View → Show Menu Bar Extra** (⌘B) or in Settings. While the extra is on, there is no Dock icon; close the window and the extra keeps running. Turn the extra off to put the app back in the Dock.

The Neural Engine graph stays at zero until something actually uses it (Core ML, Photos, on-device dictation, and similar). **Watts are measured** energy-model data. **Activity percent is estimated** as ANE power divided by a typical peak for the chip — an activity indicator, not literal ANE occupancy. The interface marks that percent with a tilde (`ANE ~37%`).

The header shows the telemetry mode (**Full IOReport**, **Partial IOReport**, or **CPU fallback**). Before the first reading it says **Sampling**. Individual metrics are labeled Measured, Estimated, Partial, or Unavailable — Hardware has the full table, including DRAM and GPU SRAM. Chip power (CPU + GPU + ANE) is Measured only when all three energy channels exist; otherwise it is Partial or Unavailable. A stuck-at-zero aggregate rail falls through to the cluster counters. Process lists are collected only while that page is open. Temperature updates about every 3 seconds. The Temperatures page lists every sensor that reports a reading, not only the CPU and GPU averages. Sensor names are written in plain language, such as Performance cluster sensor, Package, and Storage channel. Sensors of the same kind are shown as one reading: one efficiency cluster, one performance cluster, one GPU, one package, and so on. The small line under each name is the sensor count and the range. Hover a row to see Apple’s original sensor id.

Cluster letters come from the Mac (`hw.perflevel` names): Efficiency (E), Performance (P), and Super (S) on chips that have them. Frequency tables are read from the power-manager registry. M1–M3 store those steps in hertz. M4 and later store the CPU clusters in kilohertz and also publish hertz tables for other parts of the chip. Silicon Scope uses the kilohertz ladders for the CPU when those reach a CPU clock, and turns either encoding into MHz. Pages scroll when the window is shorter than the dashboard.

## Notes

- No administrator password is required.
- IOReport, HID thermal sensors, and SMC keys are undocumented Apple interfaces. Channel names can change between chips and macOS versions; the sampler filters conservatively and falls back to `host_processor_info` for CPU if IOReport is unavailable. Missing channels show as Unavailable rather than a fake zero. Temperature prefers HID cluster diodes, then SMC core and GPU keys, then the power-manager die sensors.
- App icon `@2x` filenames are the normal Apple `.iconset` convention for 2× scale slots (built by `Scripts/GenerateAppIcon.swift`).

## Project layout

```
SiliconScope/
├── Package.swift
├── AppInfo.plist
├── CHANGELOG.md
├── README.md
├── build-app.sh
├── Scripts/GenerateAppIcon.swift
├── Assets/
├── Sources/SiliconScope/          # App UI + entry
├── Sources/SiliconScopeCore/      # Sampling + math
└── Tests/SiliconScopeCoreTests/
```

## License

Copyright © 2026. All rights reserved.
