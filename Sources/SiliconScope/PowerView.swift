import SiliconScopeCore
import SwiftUI

struct PowerView: View {
    @EnvironmentObject var store: MetricStore

    var body: some View {
        let snap = store.latest
        VStack(spacing: 12) {
            Panel(title: "Stacked package power", accessory: MetricFormat.value(MetricFormat.watts(snap.packagePowerWatts), quality: snap.confidence.power), quality: snap.confidence.power) {
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
                .frame(minHeight: 230)
            }

            HStack(spacing: 12) {
                powerCard("CPU", snap.cpuPowerWatts, AppTheme.cpu, ChartSeries.watts(store.history, \.cpuPowerWatts, series: "CPU"), snap.confidence.cpuPower)
                powerCard("GPU", snap.gpuPowerWatts, AppTheme.gpu, ChartSeries.watts(store.history, \.gpuPowerWatts, series: "GPU"), snap.confidence.gpuPower)
                powerCard("Neural Engine", snap.anePowerWatts, AppTheme.ane, ChartSeries.watts(store.history, \.anePowerWatts, series: "ANE"), snap.confidence.aneWatts)
            }

            HStack(spacing: 12) {
                StatCell(label: "DRAM", value: MetricFormat.value(MetricFormat.watts(snap.ramPowerWatts), quality: snap.confidence.dram), quality: snap.confidence.dram)
                    .padding(12)
                    .background(card)
                StatCell(label: "GPU SRAM", value: MetricFormat.value(MetricFormat.watts(snap.gpuSRAMPowerWatts), quality: snap.confidence.gpuSRAM), quality: snap.confidence.gpuSRAM)
                    .padding(12)
                    .background(card)
                StatCell(label: "CPU + GPU + ANE", value: MetricFormat.value(MetricFormat.watts(snap.packagePowerWatts), quality: snap.confidence.power), color: AppTheme.power, quality: snap.confidence.power)
                    .padding(12)
                    .background(card)
                StatCell(label: "Sample window", value: String(format: "%.1f s", store.interval))
                    .padding(12)
                    .background(card)
            }
        }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(AppTheme.card)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.rule, lineWidth: 1))
    }

    private func powerCard(_ title: String, _ watts: Double, _ color: Color, _ points: [HistoryLine], _ quality: MetricQuality) -> some View {
        Panel(title: title, accessory: MetricFormat.value(MetricFormat.watts(watts), quality: quality), quality: quality) {
            AreaHistoryChart(
                points: points,
                color: color,
                maxValue: max(points.map(\.value).max() ?? 1, 0.5),
                unitLabel: "Watts"
            )
            .frame(minHeight: 120)
        }
    }
}
