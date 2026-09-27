import SiliconScopeCore
import SwiftUI

struct GPUView: View {
    @EnvironmentObject var store: MetricStore

    var body: some View {
        let snap = store.latest
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Panel(title: "GPU active residency", quality: snap.confidence.gpu) {
                    AreaHistoryChart(
                        points: ChartSeries.ratio(store.history, \.gpuActiveRatio, series: "GPU"),
                        color: AppTheme.gpu,
                        maxValue: 1
                    )
                    .frame(minHeight: 200)
                }
                Panel(title: "GPU power", quality: snap.confidence.gpuPower) {
                    AreaHistoryChart(
                        points: ChartSeries.watts(store.history, \.gpuPowerWatts, series: "GPU W"),
                        color: AppTheme.power,
                        maxValue: max(store.history.map(\.gpuPowerWatts).max() ?? 1, 1),
                        unitLabel: "Watts"
                    )
                    .frame(minHeight: 200)
                }
            }

            HStack(spacing: 12) {
                Panel(title: "Now", quality: snap.confidence.gpu) {
                    VStack(alignment: .leading, spacing: 14) {
                        RingGauge(
                            progress: snap.gpuActiveRatio,
                            color: AppTheme.gpu,
                            label: "Active residency",
                            detail: MetricFormat.percent(snap.gpuActiveRatio)
                        )
                        RingGauge(
                            progress: snap.gpuScaledRatio,
                            color: AppTheme.cpu,
                            label: "Frequency-scaled",
                            detail: MetricFormat.percent(snap.gpuScaledRatio)
                        )
                    }
                }
                Panel(title: "Details") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 14) {
                        StatCell(label: "Frequency", value: MetricFormat.value(MetricFormat.megahertz(snap.gpuFrequencyMHz), quality: snap.confidence.gpu), color: AppTheme.gpu, quality: snap.confidence.gpu)
                        StatCell(label: "Power", value: MetricFormat.value(MetricFormat.watts(snap.gpuPowerWatts), quality: snap.confidence.gpuPower), color: AppTheme.power, quality: snap.confidence.gpuPower)
                        StatCell(label: "GPU SRAM", value: MetricFormat.value(MetricFormat.watts(snap.gpuSRAMPowerWatts), quality: snap.confidence.gpuSRAM), quality: snap.confidence.gpuSRAM)
                        StatCell(label: "Temperature", value: MetricFormat.temperature(snap.gpuTempC), quality: snap.confidence.temperature)
                        StatCell(label: "GPU cores", value: "\(store.hardware.gpuCoreCount)")
                        StatCell(
                            label: "DVFS steps",
                            value: store.hardware.gpuFrequenciesMHz.isEmpty
                                ? "—"
                                : store.hardware.gpuFrequenciesMHz.map { "\($0)" }.joined(separator: ", ")
                        )
                    }
                }
            }

            Text("Active residency is the share of the sample spent doing GPU work. Scaled residency weights that time by operating frequency versus the GPU’s maximum DVFS step.")
                .font(AppTheme.small)
                .foregroundStyle(AppTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
