import SiliconScopeCore
import SwiftUI

struct TemperaturesView: View {
    @EnvironmentObject var store: MetricStore

    private var sensors: [TemperatureSensor] {
        store.latest.sensors.sorted { lhs, rhs in
            if lhs.group.sortOrder != rhs.group.sortOrder { return lhs.group.sortOrder < rhs.group.sortOrder }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    var body: some View {
        let snap = store.latest
        let grouped = TemperatureGroup.allCases.compactMap { group -> (TemperatureGroup, [TemperatureSensor])? in
            let rows = sensors.filter { $0.group == group }
            return rows.isEmpty ? nil : (group, rows)
        }
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                summary("Hottest", hottest.map { MetricFormat.temperature($0.celsius) } ?? "—", AppTheme.danger)
                summary("CPU", MetricFormat.temperature(snap.cpuTempC), AppTheme.cpu)
                summary("GPU", MetricFormat.temperature(snap.gpuTempC), AppTheme.gpu)
                summary("Sensors", sensors.isEmpty ? "—" : "\(sensors.count)", AppTheme.ink)
            }

            if grouped.isEmpty {
                Panel(title: "Sensors", quality: snap.confidence.temperature) {
                    Text(store.hasSample
                         ? "No temperature sensors reported a reading."
                         : "Waiting for the first sensor reading.")
                        .font(AppTheme.small)
                        .foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                }
            } else {
                ForEach(grouped, id: \.0) { group, rows in
                    Panel(title: group.title, accessory: panelAccessory(group, rows)) {
                        VStack(spacing: 8) {
                            ForEach(readings(from: rows)) { cluster in
                                clusterRow(cluster)
                            }
                        }
                    }
                }
            }
        }
    }

    private var hottest: TemperatureSensor? {
        sensors.max { $0.celsius < $1.celsius }
    }

    private func summary(_ label: String, _ value: String, _ color: Color) -> some View {
        StatCell(label: label, value: value, color: color)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.rule, lineWidth: 1))
            )
    }

    private func panelAccessory(_ group: TemperatureGroup, _ rows: [TemperatureSensor]) -> String {
        let count = readings(from: rows).count
        if group == .cpu { return count == 1 ? "1 cluster" : "\(count) clusters" }
        return count == 1 ? "1 group" : "\(count) groups"
    }

    private func readings(from sensors: [TemperatureSensor]) -> [ClusterReading] {
        let families = Dictionary(grouping: sensors, by: { TemperatureName.family(for: $0.name) })
        return families.compactMap { title, members in
            clusterReading(title, members)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func clusterReading(_ title: String, _ sensors: [TemperatureSensor]) -> ClusterReading? {
        let values = sensors.map(\.celsius)
        guard let low = values.min(), let high = values.max() else { return nil }
        return ClusterReading(
            id: title,
            title: title,
            celsius: values.reduce(0, +) / Double(values.count),
            low: low,
            high: high,
            count: values.count,
            sources: sensors.map(\.name).sorted().joined(separator: "\n")
        )
    }

    private func clusterRow(_ cluster: ClusterReading) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cluster.title)
                    .font(AppTheme.small)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Text(cluster.detail)
                    .font(AppTheme.micro)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            meter(cluster.celsius)
            reading(cluster.celsius)
        }
        .padding(.vertical, 4)
        .help(cluster.sources)
    }

    private func meter(_ celsius: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AppTheme.panel)
                Capsule()
                    .fill(temperatureColor(celsius))
                    .frame(width: max(4, geo.size.width * temperatureFill(celsius)))
            }
        }
        .frame(width: 140, height: 6)
    }

    private func reading(_ celsius: Double) -> some View {
        Text(MetricFormat.temperature(celsius))
            .font(AppTheme.mono)
            .foregroundStyle(temperatureColor(celsius))
            .frame(width: 64, alignment: .trailing)
    }

    private func temperatureFill(_ celsius: Double) -> Double {
        min(1, max(0, (celsius - 20) / 80))
    }

    private func temperatureColor(_ celsius: Double) -> Color {
        if celsius >= 80 { return AppTheme.danger }
        if celsius >= 60 { return AppTheme.warn }
        return AppTheme.ok
    }
}

private struct ClusterReading: Identifiable {
    var id: String
    var title: String
    var celsius: Double
    var low: Double
    var high: Double
    var count: Int
    var sources: String

    var detail: String {
        let countText = count == 1 ? "1 sensor" : "\(count) sensors"
        guard count > 1 else { return countText }
        return "\(countText) · \(MetricFormat.temperature(low))–\(MetricFormat.temperature(high))"
    }
}

private extension TemperatureGroup {
    var sortOrder: Int {
        switch self {
        case .cpu: return 0
        case .gpu: return 1
        case .other: return 2
        }
    }
}
