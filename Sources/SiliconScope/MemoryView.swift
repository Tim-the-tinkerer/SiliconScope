import SiliconScopeCore
import SwiftUI

struct MemoryView: View {
    @EnvironmentObject var store: MetricStore

    var body: some View {
        let mem = store.latest.memory
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Panel(title: "Used unified memory") {
                    AreaHistoryChart(
                        points: ChartSeries.custom(store.history, series: "Used") { $0.memory.usedRatio },
                        color: AppTheme.memory,
                        maxValue: 1
                    )
                    .frame(minHeight: 190)
                }
                Panel(title: "Breakdown") {
                    MemoryDonut(memory: mem)
                        .frame(minHeight: 190)
                }
            }

            HStack(spacing: 12) {
                stat("Used", MetricFormat.bytes(mem.usedBytes), AppTheme.memory)
                stat("App", MetricFormat.bytes(mem.appBytes), AppTheme.cpu)
                stat("Wired", MetricFormat.bytes(mem.wiredBytes), AppTheme.power)
                stat("Compressed", MetricFormat.bytes(mem.compressedBytes), AppTheme.ane)
                stat("Cached files", MetricFormat.bytes(mem.cachedFilesBytes), AppTheme.muted)
                stat("Free", MetricFormat.bytes(mem.freeBytes), AppTheme.ok)
            }

            HStack(spacing: 12) {
                Panel(title: "Swap") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(MetricFormat.bytes(mem.swapUsedBytes))
                                .font(AppTheme.value)
                                .foregroundStyle(mem.swapUsedBytes > 0 ? AppTheme.warn : AppTheme.ink)
                            Text("of \(MetricFormat.bytes(mem.swapTotalBytes))")
                                .font(AppTheme.small)
                                .foregroundStyle(AppTheme.muted)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(AppTheme.faint)
                                Capsule()
                                    .fill(AppTheme.warn)
                                    .frame(width: max(0, geo.size.width * mem.swapRatio))
                            }
                        }
                        .frame(height: 8)
                        Text("Swap is compressed memory overflow onto disk. Occasional use is normal; a large persistent amount usually means the working set exceeds RAM.")
                            .font(AppTheme.small)
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                Panel(title: "Pressure", accessory: mem.pressure.title) {
                    VStack(alignment: .leading, spacing: 10) {
                        PressureHistoryChart(history: store.history)
                            .frame(minHeight: 128)
                        HStack(spacing: 8) {
                            Circle()
                                .fill(AppTheme.pressureColor(mem.pressure))
                                .frame(width: 10, height: 10)
                            Text(mem.pressure.title)
                                .font(AppTheme.section)
                                .foregroundStyle(AppTheme.pressureColor(mem.pressure))
                        }
                        Text("macOS reports memory pressure from the jetsam / memorystatus subsystem. Warning and above means the compressor and reclaim paths are working harder.")
                            .font(AppTheme.small)
                            .foregroundStyle(AppTheme.muted)
                        StatCell(label: "DRAM energy", value: MetricFormat.value(MetricFormat.watts(store.latest.ramPowerWatts), quality: store.latest.confidence.dram), color: AppTheme.power, quality: store.latest.confidence.dram)
                    }
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        StatCell(label: title, value: value, color: color)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.rule, lineWidth: 1))
            )
    }
}
