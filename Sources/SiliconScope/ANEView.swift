import SiliconScopeCore
import SwiftUI

struct ANEView: View {
    @EnvironmentObject var store: MetricStore

    var body: some View {
        let snap = store.latest
        let activity = store.aneActivity()
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Panel(title: "Neural Engine power", quality: snap.confidence.aneWatts) {
                    AreaHistoryChart(
                        points: ChartSeries.watts(store.history, \.anePowerWatts, series: "ANE"),
                        color: AppTheme.ane,
                        maxValue: max(store.history.map(\.anePowerWatts).max() ?? store.hardware.anePeakWatts, 0.5),
                        unitLabel: "Watts"
                    )
                    .frame(minHeight: 210)
                }
                Panel(title: "Estimated activity", quality: snap.confidence.aneActivity) {
                    AreaHistoryChart(
                        points: ChartSeries.custom(store.history, series: "ANE activity") { store.aneActivity(in: $0) },
                        color: AppTheme.cpu,
                        maxValue: 1
                    )
                    .frame(minHeight: 210)
                }
            }

            HStack(spacing: 12) {
                Panel(title: "Now") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(MetricFormat.value(MetricFormat.watts(snap.anePowerWatts), quality: snap.confidence.aneWatts))
                            .font(AppTheme.hero)
                            .foregroundStyle(AppTheme.ane)
                        Text(snap.confidence.aneWatts == .measured ? "Measured energy-model watts" : "ANE energy channel unavailable")
                            .font(AppTheme.small)
                            .foregroundStyle(AppTheme.muted)
                        RingGauge(
                            progress: activity,
                            color: AppTheme.ane,
                            label: "ANE activity",
                            detail: "\(MetricFormat.estimatedPercent(activity)) of \(MetricFormat.watts(store.hardware.anePeakWatts)) typical peak",
                            estimated: true
                        )
                        Text("The Neural Engine is power-gated when idle, so this graph sits at zero unless Core ML, vision, or another on-device model is running. Activity is estimated from power, not occupancy.")
                            .font(AppTheme.small)
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                Panel(title: "How this is measured") {
                    VStack(alignment: .leading, spacing: 10) {
                        StatCell(label: "Energy channel", value: "IOReport PMP / Energy Model")
                        StatCell(label: "Watts", value: snap.confidence.aneWatts.title, quality: snap.confidence.aneWatts)
                        StatCell(label: "Activity %", value: snap.confidence.aneActivity.title, quality: snap.confidence.aneActivity)
                        StatCell(label: "Typical peak", value: MetricFormat.watts(store.hardware.anePeakWatts))
                        StatCell(label: "Package share", value: MetricFormat.percent(
                            MetricMath.ratio(snap.anePowerWatts, max(snap.packagePowerWatts, 0.001))
                        ))
                        Text("Apple does not publish a public ANE occupancy counter. Watts come from the same energy-model channel `powermetrics` uses. Activity is estimated as that power divided by a typical peak for \(store.hardware.chipName) — an activity indicator, not processor occupancy.")
                            .font(AppTheme.small)
                            .foregroundStyle(AppTheme.muted)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }
}
