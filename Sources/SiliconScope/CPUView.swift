import SiliconScopeCore
import SwiftUI

struct CPUView: View {
    @EnvironmentObject var store: MetricStore

    var body: some View {
        let snap = store.latest
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Panel(title: "Active residency", quality: snap.confidence.cpu) {
                    AreaHistoryChart(
                        points: ChartSeries.ratio(store.history, \.cpuActiveRatio, series: "CPU"),
                        color: AppTheme.cpu,
                        maxValue: 1
                    )
                    .frame(minHeight: 170)
                }
                Panel(title: "Clusters") {
                    MultiSeriesChart(
                        points:
                            ChartSeries.ratio(store.history, \.pClusterActiveRatio, series: "\(store.hardware.pCoreLabel)-cores")
                            + ChartSeries.ratio(store.history, \.eClusterActiveRatio, series: "\(store.hardware.eCoreLabel)-cores"),
                        colors: [
                            "\(store.hardware.pCoreLabel)-cores": AppTheme.cpu,
                            "\(store.hardware.eCoreLabel)-cores": AppTheme.ane,
                        ],
                        maxValue: 1
                    )
                    .frame(minHeight: 170)
                }
            }

            HStack(spacing: 12) {
                Panel(title: "\(store.hardware.pClusterName) \(store.hardware.pCoreLabel)-cluster") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                        StatCell(label: "Active", value: MetricFormat.percent(snap.pClusterActiveRatio), color: AppTheme.cpu)
                        StatCell(label: "Scaled", value: MetricFormat.percent(snap.pClusterScaledRatio))
                        StatCell(label: "Frequency", value: MetricFormat.megahertz(snap.pClusterFrequencyMHz))
                    }
                    VStack(spacing: 7) {
                        ForEach(snap.performanceCores) { core in
                            CoreBarRow(core: core, color: AppTheme.cpu, clusterLabel: store.hardware.pCoreLabel)
                        }
                    }
                    .padding(.top, 8)
                }
                Panel(title: "\(store.hardware.eClusterName) \(store.hardware.eCoreLabel)-cluster") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                        StatCell(label: "Active", value: MetricFormat.percent(snap.eClusterActiveRatio), color: AppTheme.ane)
                        StatCell(label: "Scaled", value: MetricFormat.percent(snap.eClusterScaledRatio))
                        StatCell(label: "Frequency", value: MetricFormat.megahertz(snap.eClusterFrequencyMHz))
                    }
                    VStack(spacing: 7) {
                        ForEach(snap.efficiencyCores) { core in
                            CoreBarRow(core: core, color: AppTheme.ane, clusterLabel: store.hardware.eCoreLabel)
                        }
                    }
                    .padding(.top, 8)
                }
            }

            HStack(spacing: 12) {
                StatCell(label: "CPU power", value: MetricFormat.value(MetricFormat.watts(snap.cpuPowerWatts), quality: snap.confidence.cpuPower), color: AppTheme.power, quality: snap.confidence.cpuPower)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.card))
                StatCell(label: "Temperature", value: MetricFormat.temperature(snap.cpuTempC), color: AppTheme.warn, quality: snap.confidence.temperature)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.card))
                StatCell(label: "Load 1 / 5 / 15", value: "\(MetricFormat.load(snap.loadAverage1))  \(MetricFormat.load(snap.loadAverage5))  \(MetricFormat.load(snap.loadAverage15))")
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.card))
                StatCell(label: "Cores", value: "\(store.hardware.pCoreCount)\(store.hardware.pCoreLabel) + \(store.hardware.eCoreCount)\(store.hardware.eCoreLabel)")
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.card))
            }
        }
    }
}
