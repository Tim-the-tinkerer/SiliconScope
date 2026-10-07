# Changelog

All notable changes to **Silicon Scope** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.1.8] — 2026-10-07

### Fixed

- Launch on M1 no longer quits when a PMP energy counter has no residency states. Those rails are plain millijoule readings, and a negative state count was trapping the sampler
- Free memory no longer counts speculative pages twice. Those pages are already inside the kernel free count
- SMC temperatures are tried again if the first open fails, instead of staying blank for the rest of the session
- Process names fall back to the kernel’s registered name and command when `proc_name` is empty
- A residency channel’s integer sentinel is not treated as an energy reading
- A core with no active residency draws an empty bar instead of a short stub
- Temperatures no longer lists every SMC key. Those keys fill in the performance cluster, efficiency cluster, and GPU only when the chip does not publish those HID diodes. The extra Other rows were unnamed SMC keys
- The performance-cluster row says it is the diodes on the performance cores, read together. It is not one sensor per core

## [1.1.7] — 2026-10-07

### Fixed

- CPU frequency on M4 uses the kilohertz cluster ladders. Hertz tables that peak near 2 GHz are other domains and are no longer treated as the efficiency cores
- Per-core labels on M4 are sequential (E0–E3 and P0–P9). A powered-off performance cluster no longer pulls the cluster frequency down to its minimum clock
- CPU power uses the PMP energy histograms when the Energy Model CPU counters stay at zero. A sleeping cluster’s sparse bins are not counted as continuous watts
- Temperature on M4 Pro and M2 Pro includes the SMC core and GPU sensors. Those chips do not publish the HID performance, efficiency, and GPU diodes. Duplicate PMU copies are combined, and the calibration constant is omitted

## [1.1.6] — 2026-09-27

### Fixed

- Switching drives while details are loading no longer shows the previous drive’s details under the new selection
- Overview’s height budget matches the bottom row, so that row is not eight points taller than the space reserved for it

## [1.1.5] — 2026-09-27

### Changed

- Overview panels grow and shrink with the window
- About Silicon Scope opens from the app menu and the sidebar

## [1.1.4] — 2026-09-27

### Fixed

- Network totals count Wi-Fi and Ethernet. A VPN stays in the interface list and is added to the total only when those links are down
- Disk details run one read at a time. A new read waits until the current one finishes
- Process CPU keeps a baseline only when the process ID and the process start time still match

## [1.1.3] — 2026-09-27

### Changed

- Disk hardware is scanned about every two seconds, or immediately when a volume is mounted or unmounted. Free space still updates on each sample
- History charts keep the readings they draw. Per-core samples stay on the latest reading instead of in the chart history
- Network interface names and addresses are reused for a few seconds. Download and upload rates still update on each sample

### Fixed

- Network sampling keeps running when an interface message is not aligned, and a changing interface list is read again instead of blanking the rates for one interval
- A process ID that is reused no longer shows a huge CPU percent
- Power and network charts keep each series on its own color
- Disk details wait for the current read to finish instead of starting another one on every sample

## [1.1.2] — 2026-09-27

### Added

- Menu bar extra shows CPU and GPU temperature. CPU temperature is the average of the performance-cluster and efficiency-cluster readings
- Network page shows download and upload, a three-minute chart, and each active interface
- Disk page shows internal, external, and network drives, with free space and the volumes mounted on each
- Click a drive for storage details, activity since boot, and SMART data when the drive reports it
- Overview shows basic temperature, network, and disk readings. Click a summary to open that page

## [1.1.1] — 2026-09-27

### Added

- Temperatures page lists every temperature sensor, grouped into CPU, GPU, and other
- Temperature sensors use plain names, such as Performance cluster sensor and Package, instead of the raw sensor id
- Efficiency and performance temperature diodes are shown as one reading per cluster
- The other temperature sensors are grouped the same way, one reading per kind

## [1.1.0] — 2026-09-27

### Added

- Memory page shows a three-minute graph of memory pressure (Normal, Warning, Urgent, Critical)
- Processes column headers sort by name, PID, CPU, memory, or threads. Click the active column again to reverse the order
- Name and memory sorts keep that order. A new sample does not rebuild the list from CPU rank
- Click a process to inspect its path, owner, parent, CPU time, memory, and activity counts
- Process search filters the list by name or PID, including processes outside the CPU top 20
- The full process list scrolls by drawing only the rows on screen
- Right-click a process to show details, copy its name, PID, or path, reveal it in Finder, or quit it

## [1.0.9] — 2026-09-27

### Fixed

- Sampling no longer accumulates memory while the app sits open. Each IOReport sample is released, and the sampler thread drains its autorelease pool every cycle
- Cluster labels follow `hw.perflevelN.name` (Efficiency, Performance, Super) instead of a chip-name guess
- DVFS tables are discovered from the power-manager registry. Frequencies decode as Hz or kHz from the value itself, so M4 and M5 tables still land on MHz
- A stuck-at-zero CPU or Neural Engine aggregate falls through to the cluster counters. A real idle, with every rail near zero, stays zero
- DRAM and GPU SRAM show as unavailable when those channels are missing
- Cached memory includes purgeable pages
- Per-core labels use the cluster letter, and a second die is marked in the label
- The header shows Sampling until the first reading, instead of CPU fallback
- An empty CPU fallback sample is Unavailable
- Thermal sampling keeps one HID client and also reads AGX graphics sensors
- Memory pressure level 0 is Normal and level 8 is Critical
- Pages scroll when the window is shorter than the dashboard
- GPU residency falls back to another GPU performance-state channel when GPUPH is absent
- Settings refreshes the login-item status when the app becomes active again
- `SiliconScope --sample` prints CPU and GPU temperature

## [1.0.8] — 2026-08-31

### Fixed

- Menu bar extra no longer wraps to two lines (and off the top of the screen) when a reading hits `100%` / `ANE ~100%`

## [1.0.7] — 2026-08-31

### Fixed

- Menu bar extra keeps sampling and live-updating while its dropdown is open (event-tracking run-loop mode)

## [1.0.6] — 2026-08-31

### Added

- Menu bar extra dropdown shows memory pressure (Normal / Warning / Urgent / Critical) next to the memory stats
- **Partial** metric quality for chip / package power when some energy rails are missing

### Changed

- Chip power is Measured only when CPU, GPU, and ANE energy channels are all present. Individual rails stay independently Measured or Unavailable
- CPU and GPU power panels use their own energy-channel confidence, not the package aggregate

## [1.0.5] — 2026-08-31

### Added

- Settings panel (⌘,) for polling interval, open at login, open window at launch, and the menu bar extra
- Launch-at-login via macOS Login Items (`SMAppService`)

### Changed

- Sample interval is remembered between launches
- Turning the menu bar extra off always brings the main window forward instead of quitting when no window is visible

## [1.0.4] — 2026-08-31

### Changed

- Menu bar extra is tighter: 2-digit padding, single spaces, no reserved column for `100%`

## [1.0.3] — 2026-08-31

### Fixed

- Menu bar extra uses a fixed slot and digit-width padding so `8%` vs `100%` no longer shoves neighboring extras left and right

## [1.0.2] — 2026-08-31

### Added

- Telemetry mode in the header and on Hardware: Full IOReport, Partial IOReport, or CPU fallback
- Per-metric confidence badges: Measured, Estimated, Unavailable (especially ANE watts vs activity)
- Process sampling only while the Processes page is open

### Changed

- History is a three-minute time window, not a 180-sample cap, so 0.5 s / 1 s / 2 s intervals all show the same duration
- HID temperature polling is every 3 seconds instead of every telemetry cycle
- ANE percent is labeled **estimated activity**, not utilization or occupancy. Display uses a tilde (`ANE ~37%`). Watts remain the measured energy-model figure
- Menu bar extra uses `CPU` / `GPU` / `MEM` / `ANE` instead of one-letter codes; the dropdown spells out processor, graphics, memory, and Neural Engine
- Window tabbing is off. Pages live in the sidebar; macOS was injecting a tab bar because the window is resizable
- With the menu bar extra on, Silicon Scope is an accessory app and does not appear in the Dock. Turning the extra off restores the Dock icon. The window still opens from the extra.

## [1.0.1] — 2026-08-18

### Added

- Menu bar extra with live CPU, GPU, memory, and Neural Engine percentages
- Status-item dropdown with watts, frequencies, Open Window, pause, and quit
- **View → Show Menu Bar Extra** (⌘B). Closing the window keeps the app in the menu bar when the extra is on

## [1.0.0] — 2026-08-18

### Added

- Native macOS app with live CPU, GPU, memory, and Apple Neural Engine telemetry
- IOReport sampling for cluster residency, GPU frequency, and Energy Model watts without sudo
- Detail pages for CPU cores, GPU, unified memory, Neural Engine, package power, processes, and hardware
- History charts, per-core bars, memory donut, and stacked power graph
- `SiliconScopeCore` library with unit tests for metric math and formatters
- SwiftPM project, `build-app.sh` packaging, and app icon
