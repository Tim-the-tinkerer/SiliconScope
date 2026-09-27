import SiliconScopeCore
import SwiftUI

struct HardwareView: View {
    @EnvironmentObject var store: MetricStore

    var body: some View {
        let hw = store.hardware
        let snap = store.latest
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Panel(title: "Chip") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(hw.chipName)
                            .font(AppTheme.hero)
                            .foregroundStyle(AppTheme.ink)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                            StatCell(label: "Model", value: hw.modelIdentifier)
                            StatCell(label: "Unified memory", value: MetricFormat.bytes(hw.memoryBytes))
                            StatCell(label: "CPU cores", value: "\(hw.pCoreCount) \(hw.pCoreLabel) + \(hw.eCoreCount) \(hw.eCoreLabel)")
                            StatCell(label: "GPU cores", value: "\(hw.gpuCoreCount)")
                            StatCell(label: "ANE typical peak", value: MetricFormat.watts(hw.anePeakWatts), color: AppTheme.ane)
                            StatCell(label: "Architecture", value: hw.isAppleSilicon ? "Apple Silicon" : "Intel")
                        }
                    }
                }
                Panel(title: "Runtime") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                        StatCell(label: "Uptime", value: MetricFormat.uptime(snap.uptime))
                        StatCell(label: "Interval", value: String(format: "%.1f s", store.interval))
                        StatCell(label: "History", value: "\(store.history.count) samples · \(MetricFormat.historyWindow(store.historyWindow))")
                        StatCell(label: "CPU temp", value: MetricFormat.temperature(snap.cpuTempC), quality: snap.confidence.temperature)
                        StatCell(label: "GPU temp", value: MetricFormat.temperature(snap.gpuTempC), quality: snap.confidence.temperature)
                        StatCell(label: "Processes", value: snap.confidence.processes == .measured ? "Sampling" : "On this page only")
                    }
                }
            }

            Panel(title: "Telemetry mode", accessory: store.hasSample ? snap.confidence.mode.title : "Sampling") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(store.hasSample ? snap.confidence.mode.detail : "Taking the first sample.")
                        .font(AppTheme.small)
                        .foregroundStyle(AppTheme.muted)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                        StatCell(label: "CPU", value: snap.confidence.cpu.title, quality: snap.confidence.cpu)
                        StatCell(label: "GPU", value: snap.confidence.gpu.title, quality: snap.confidence.gpu)
                        StatCell(label: "ANE watts", value: snap.confidence.aneWatts.title, quality: snap.confidence.aneWatts)
                        StatCell(label: "ANE activity", value: snap.confidence.aneActivity.title, quality: snap.confidence.aneActivity)
                        StatCell(label: "CPU power", value: snap.confidence.cpuPower.title, quality: snap.confidence.cpuPower)
                        StatCell(label: "GPU power", value: snap.confidence.gpuPower.title, quality: snap.confidence.gpuPower)
                        StatCell(label: "Chip power", value: snap.confidence.power.title, quality: snap.confidence.power)
                        StatCell(label: "Memory", value: snap.confidence.memory.title, quality: snap.confidence.memory)
                        StatCell(label: "Temperature", value: snap.confidence.temperature.title, quality: snap.confidence.temperature)
                        StatCell(label: "DRAM", value: snap.confidence.dram.title, quality: snap.confidence.dram)
                        StatCell(label: "GPU SRAM", value: snap.confidence.gpuSRAM.title, quality: snap.confidence.gpuSRAM)
                        StatCell(label: "Processes", value: snap.confidence.processes.title, quality: snap.confidence.processes)
                    }
                }
            }

            HStack(spacing: 12) {
                freqPanel("\(hw.pCoreLabel)-core DVFS", hw.pCoreFrequenciesMHz, AppTheme.cpu)
                freqPanel("\(hw.eCoreLabel)-core DVFS", hw.eCoreFrequenciesMHz, AppTheme.ane)
                freqPanel("GPU DVFS", hw.gpuFrequenciesMHz, AppTheme.gpu)
            }

            Text("CPU, GPU, and Neural Engine watts come from the private IOReport Energy Model — the same source `powermetrics` uses — without requiring an administrator password. ANE activity percent is estimated (power / typical peak), not occupancy. Temperature uses HID thermal sensors every few seconds when the OS exposes them. Process lists are sampled only while that page is open.")
                .font(AppTheme.small)
                .foregroundStyle(AppTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func freqPanel(_ title: String, _ freqs: [UInt32], _ color: Color) -> some View {
        Panel(title: title, accessory: freqs.isEmpty ? "unavailable" : "\(freqs.count) steps") {
            if freqs.isEmpty {
                Text("No DVFS table found.")
                    .font(AppTheme.small)
                    .foregroundStyle(AppTheme.muted)
            } else {
                FlexibleFreqs(values: freqs, color: color)
            }
        }
    }
}

private struct FlexibleFreqs: View {
    var values: [UInt32]
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, freq in
                HStack {
                    Capsule()
                        .fill(color.opacity(0.8))
                        .frame(width: 8, height: 8)
                    Text(MetricFormat.megahertz(freq))
                        .font(AppTheme.mono)
                        .foregroundStyle(AppTheme.ink)
                }
            }
        }
    }
}
