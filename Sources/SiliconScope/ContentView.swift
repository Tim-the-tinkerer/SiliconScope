import SiliconScopeCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: MetricStore

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 188, idealWidth: 200, maxWidth: 230)
            detail
                .frame(minWidth: 720)
        }
        .background(AppTheme.bg)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SILICON SCOPE")
                    .font(AppTheme.micro)
                    .foregroundStyle(AppTheme.muted)
                    .tracking(1.2)
                Text(store.hardware.chipName)
                    .font(AppTheme.section)
                    .foregroundStyle(AppTheme.ink)
                Text(store.hardware.modelIdentifier)
                    .font(AppTheme.small)
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 12)

            livePills
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(SidebarPage.allCases) { item in
                        Button {
                            store.page = item
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(item.tint)
                                    .frame(width: 16)
                                Text(item.title)
                                    .font(AppTheme.body)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(store.page == item ? AppTheme.cardHover : Color.clear)
                            )
                            .foregroundStyle(store.page == item ? AppTheme.ink : AppTheme.muted)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                Button {
                    store.togglePaused()
                } label: {
                    Label(store.paused ? "Resume" : "Pause", systemImage: store.paused ? "play.fill" : "pause.fill")
                        .font(AppTheme.small)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.cpu)
                Spacer()
                Button {
                    AppDelegate.shared.showAbout()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.muted)
                .help("About Silicon Scope")
                Button {
                    AppDelegate.shared.showSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.muted)
                .help("Settings")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Picker("Interval", selection: $store.interval) {
                ForEach(MetricStore.allowedIntervals, id: \.self) { value in
                    Text(value == 0.5 ? "0.5s" : value == 2 ? "2s" : "1s").tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(AppTheme.panel)
    }

    private var livePills: some View {
        VStack(spacing: 6) {
            miniMeter("CPU", store.latest.cpuActiveRatio, AppTheme.cpu)
            miniMeter("GPU", store.latest.gpuActiveRatio, AppTheme.gpu)
            miniMeter("MEM", store.latest.memory.usedRatio, AppTheme.memory)
            miniMeter("ANE", store.aneActivity(), AppTheme.ane, estimated: true)
        }
    }

    private func miniMeter(_ title: String, _ value: Double, _ color: Color, estimated: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(AppTheme.micro)
                .foregroundStyle(AppTheme.muted)
                .frame(width: 28, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.faint)
                    Capsule()
                        .fill(color)
                        .frame(width: max(2, geo.size.width * MetricMath.clamp01(value)))
                }
            }
            .frame(height: 5)
            Text(estimated
                 ? MetricFormat.estimatedPercent(value, digits: 0)
                 : MetricFormat.percent(value, digits: 0))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 40, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var detail: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AppTheme.rule)
            GeometryReader { proxy in
                if store.page == .processes {
                    ProcessesView()
                        .padding(16)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                } else if store.page == .overview {
                    OverviewView()
                        .padding(16)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                } else {
                    ScrollView {
                        page
                            .padding(16)
                            .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                    }
                }
            }
        }
        .background(AppTheme.bg)
    }

    @ViewBuilder
    private var page: some View {
        switch store.page {
        case .overview: OverviewView()
        case .cpu: CPUView()
        case .gpu: GPUView()
        case .memory: MemoryView()
        case .ane: ANEView()
        case .power: PowerView()
        case .temperatures: TemperaturesView()
        case .network: NetworkView()
        case .disk: DiskView()
        case .processes: ProcessesView()
        case .hardware: HardwareView()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.page.title)
                    .font(AppTheme.title)
                    .foregroundStyle(AppTheme.ink)
                Text(subtitle)
                    .font(AppTheme.small)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
            if store.paused {
                Text("PAUSED")
                    .font(AppTheme.micro)
                    .foregroundStyle(AppTheme.warn)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AppTheme.warn.opacity(0.15)))
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(store.latest.timestamp, style: .time)
                    .font(AppTheme.mono)
                    .foregroundStyle(AppTheme.ink)
                Text(store.hasSample ? "\(store.latest.confidence.mode.title) · no sudo" : "Sampling · no sudo")
                    .font(AppTheme.micro)
                    .foregroundStyle(store.hasSample && store.latest.confidence.mode == .cpuFallback ? AppTheme.warn : AppTheme.muted)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(AppTheme.panel)
    }

    private var subtitle: String {
        let hw = store.hardware
        switch store.page {
        case .overview:
            return "\(hw.pCoreCount)\(hw.pCoreLabel) + \(hw.eCoreCount)\(hw.eCoreLabel) CPU  ·  \(hw.gpuCoreCount)-core GPU  ·  \(MetricFormat.bytes(hw.memoryBytes))"
        case .cpu:
            return "\(hw.pClusterName) and \(hw.eClusterName) clusters, per-core residency and frequency"
        case .gpu:
            return "\(hw.gpuCoreCount) GPU cores · frequency-scaled utilization and energy"
        case .memory:
            return "Unified memory, compressor, swap, and pressure"
        case .ane:
            return "Apple Neural Engine energy-model watts (measured) and estimated activity"
        case .power:
            return "CPU, GPU, and Neural Engine package power"
        case .temperatures:
            return "Every temperature sensor this Mac is reporting"
        case .network:
            return "Download and upload on Wi-Fi, Ethernet, and VPN"
        case .disk:
            return "Internal, external, and network drives. Click a drive for details and SMART"
        case .processes:
            return "Highest CPU and memory consumers — search, sort, click a row for details, or right-click for tasks. Sampled only while this page is open"
        case .hardware:
            return "Chip identity, DVFS tables, and telemetry confidence"
        }
    }
}
