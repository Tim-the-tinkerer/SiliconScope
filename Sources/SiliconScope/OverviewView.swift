import SiliconScopeCore
import SwiftUI

private struct OverviewLine: Identifiable {
    var id: String
    var label: String
    var value: String
}

struct OverviewView: View {
    @EnvironmentObject var store: MetricStore

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 12
            let summary: CGFloat = 156
            let minRow: CGFloat = 118
            let needed = minRow * 3 + summary + spacing * 3
            let fits = geo.size.height >= needed
            let row = fits ? (geo.size.height - summary - spacing * 3) / 3 : minRow
            let height = fits ? geo.size.height : needed
            ScrollView {
                dashboard(rowHeight: row)
                    .frame(width: geo.size.width, height: height, alignment: .top)
            }
            .scrollDisabled(fits)
        }
    }

    private func dashboard(rowHeight: CGFloat) -> some View {
        let snap = store.latest
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                hero(
                    title: "CPU",
                    value: MetricFormat.value(MetricFormat.percent(snap.cpuActiveRatio), quality: snap.confidence.cpu),
                    detail: "P \(MetricFormat.percent(snap.pClusterActiveRatio)) · E \(MetricFormat.percent(snap.eClusterActiveRatio))",
                    color: AppTheme.cpu,
                    quality: snap.confidence.cpu,
                    series: ChartSeries.ratio(store.history, \.cpuActiveRatio, series: "CPU")
                )
                hero(
                    title: "GPU",
                    value: MetricFormat.value(MetricFormat.percent(snap.gpuActiveRatio), quality: snap.confidence.gpu),
                    detail: MetricFormat.value(MetricFormat.megahertz(snap.gpuFrequencyMHz), quality: snap.confidence.gpu),
                    color: AppTheme.gpu,
                    quality: snap.confidence.gpu,
                    series: ChartSeries.ratio(store.history, \.gpuActiveRatio, series: "GPU")
                )
            }
            .frame(height: rowHeight)
            HStack(spacing: 12) {
                hero(
                    title: "Memory",
                    value: MetricFormat.value(MetricFormat.percent(snap.memory.usedRatio), quality: snap.confidence.memory),
                    detail: "\(MetricFormat.bytes(snap.memory.usedBytes)) of \(MetricFormat.bytes(snap.memory.totalBytes))",
                    color: AppTheme.memory,
                    quality: snap.confidence.memory,
                    series: ChartSeries.custom(store.history, series: "MEM") { $0.memory.usedRatio }
                )
                hero(
                    title: "ANE activity",
                    value: MetricFormat.value(MetricFormat.estimatedPercent(store.aneActivity()), quality: snap.confidence.aneActivity),
                    detail: MetricFormat.value("\(MetricFormat.watts(snap.anePowerWatts)) measured", quality: snap.confidence.aneWatts),
                    color: AppTheme.ane,
                    quality: snap.confidence.aneActivity,
                    series: ChartSeries.custom(store.history, series: "ANE") { store.aneActivity(in: $0) }
                )
            }
            .frame(height: rowHeight)
            HStack(spacing: 12) {
                Panel(title: "Package power", accessory: MetricFormat.value(MetricFormat.watts(snap.packagePowerWatts), quality: snap.confidence.power), quality: snap.confidence.power, expands: true) {
                    MultiSeriesChart(
                        points:
                            ChartSeries.watts(store.history, \.cpuPowerWatts, series: "CPU")
                            + ChartSeries.watts(store.history, \.gpuPowerWatts, series: "GPU")
                            + ChartSeries.watts(store.history, \.anePowerWatts, series: "ANE"),
                        colors: [
                            "CPU": AppTheme.cpu,
                            "GPU": AppTheme.gpu,
                            "ANE": AppTheme.ane,
                        ],
                        maxValue: max(store.history.map(\.packagePowerWatts).max() ?? 1, 5),
                        unitLabel: "Watts"
                    )
                    .frame(maxWidth: .infinity, minHeight: 36, maxHeight: .infinity)
                    HStack(spacing: 8) {
                        powerLegend(snap)
                        Spacer(minLength: 4)
                        loadReadout(snap)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Panel(title: "Memory mix", accessory: snap.memory.pressure.title, expands: true) {
                    MemoryDonut(memory: snap.memory)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: rowHeight)
            HStack(alignment: .top, spacing: 12) {
                componentCard("Temperatures", page: .temperatures) {
                    fact("CPU", MetricFormat.temperature(cpuTemperature(snap)), AppTheme.cpu)
                    fact("GPU", MetricFormat.temperature(snap.gpuTempC), AppTheme.gpu)
                    if let hottest = hottestSensor(snap) {
                        fact("Hottest", "\(hottest.name)  \(MetricFormat.temperature(hottest.celsius))", AppTheme.warn)
                    }
                }
                componentCard("Network", page: .network) {
                    fact("Download", MetricFormat.bytesPerSecond(snap.networkDownloadBytesPerSecond), AppTheme.network)
                    fact("Upload", MetricFormat.bytesPerSecond(snap.networkUploadBytesPerSecond), AppTheme.cpu)
                    fact("Links", networkSummary(snap), AppTheme.muted)
                }
                componentCard("Disk", page: .disk) {
                    fact("Free", diskFree(snap), AppTheme.disk)
                    ForEach(diskLines(snap)) { line in
                        fact(line.label, line.value, AppTheme.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 156, alignment: .top)
        }
    }

    private func cpuTemperature(_ snap: Snapshot) -> Double? {
        TemperatureName.cpuClusterAverage(snap.sensors) ?? snap.cpuTempC
    }

    private func hottestSensor(_ snap: Snapshot) -> (name: String, celsius: Double)? {
        guard let hottest = snap.sensors.max(by: { $0.celsius < $1.celsius }) else { return nil }
        return (TemperatureName.family(for: hottest.name), hottest.celsius)
    }

    private func networkSummary(_ snap: Snapshot) -> String {
        let runningPhysical = snap.networkInterfaces.filter { $0.isUp && ($0.kind == .wifi || $0.kind == .ethernet) }
        let running = runningPhysical.isEmpty
            ? snap.networkInterfaces.filter { $0.isUp && $0.kind == .vpn }
            : runningPhysical
        let busy = running.filter { $0.downloadBytesPerSecond + $0.uploadBytesPerSecond > 0 }
        let addressed = running.filter { !$0.addresses.isEmpty }
        let links = !busy.isEmpty ? busy : (!addressed.isEmpty ? addressed : running)
        if links.isEmpty { return store.hasSample ? "No active link" : "—" }
        let names = links.prefix(2).map { $0.displayName.isEmpty ? $0.name : $0.displayName }
        if links.count > 2 { return names.joined(separator: " · ") + "  +\(links.count - 2)" }
        return names.joined(separator: " · ")
    }

    private func diskFree(_ snap: Snapshot) -> String {
        let physical = snap.drives.filter(\.kind.countsTowardCapacity)
        guard !physical.isEmpty else { return store.hasSample ? "No drives" : "—" }
        let free = physical.reduce(UInt64(0)) { $0 + $1.availableBytes }
        return MetricFormat.bytes(free)
    }

    private func diskLines(_ snap: Snapshot) -> [OverviewLine] {
        let physical = snap.drives.filter(\.kind.countsTowardCapacity)
        var lines = physical.prefix(2).map { drive in
            OverviewLine(
                id: drive.id,
                label: drive.kind.title,
                value: "\(shortDriveName(drive.name))  \(MetricFormat.bytes(drive.availableBytes))"
            )
        }
        if physical.count > 2 {
            lines.append(OverviewLine(id: "more-drives", label: "More", value: "\(physical.count - 2) drives"))
        } else if lines.count < 2, let share = snap.drives.first(where: { $0.kind == .network }) {
            lines.append(OverviewLine(id: share.id, label: "Network", value: shortDriveName(share.name)))
        }
        return lines
    }

    private func shortDriveName(_ name: String) -> String {
        if name.count <= 32 { return name }
        return String(name.prefix(31)) + "…"
    }

    private func componentCard<Content: View>(_ title: String, page: SidebarPage, @ViewBuilder content: @escaping () -> Content) -> some View {
        Button {
            store.page = page
        } label: {
            Panel(title: title) {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .top)
        .help("Open \(page.title)")
    }

    private func fact(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .font(AppTheme.micro)
                .foregroundStyle(AppTheme.muted)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(AppTheme.mono)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
    }

    private func hero(title: String, value: String, detail: String, color: Color, quality: MetricQuality? = nil, series: [HistoryLine]) -> some View {
        Panel(title: title, quality: quality, expands: true) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(value)
                        .font(AppTheme.hero)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(detail)
                        .font(AppTheme.small)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            AreaHistoryChart(points: series, color: color, maxValue: 1)
                .frame(maxWidth: .infinity, minHeight: 36, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func powerLegend(_ snap: Snapshot) -> some View {
        HStack(spacing: 10) {
            legend("CPU", AppTheme.cpu, MetricFormat.value(MetricFormat.watts(snap.cpuPowerWatts), quality: snap.confidence.cpuPower))
            legend("GPU", AppTheme.gpu, MetricFormat.value(MetricFormat.watts(snap.gpuPowerWatts), quality: snap.confidence.gpuPower))
            legend("ANE", AppTheme.ane, MetricFormat.value(MetricFormat.watts(snap.anePowerWatts), quality: snap.confidence.aneWatts))
        }
    }

    private func loadReadout(_ snap: Snapshot) -> some View {
        Text("Load \(MetricFormat.load(snap.loadAverage1))  \(MetricFormat.load(snap.loadAverage5))  \(MetricFormat.load(snap.loadAverage15))")
            .font(AppTheme.mono)
            .foregroundStyle(AppTheme.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func legend(_ title: String, _ color: Color, _ value: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(title) \(value)")
                .font(AppTheme.small)
                .foregroundStyle(AppTheme.muted)
        }
    }
}
