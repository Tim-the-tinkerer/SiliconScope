import SiliconScopeCore
import SwiftUI

struct NetworkView: View {
    @EnvironmentObject var store: MetricStore

    var body: some View {
        let snap = store.latest
        let peak = max(store.history.map { max($0.networkDownloadBytesPerSecond, $0.networkUploadBytesPerSecond) }.max() ?? 0, 1)
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                rateCard("Download", snap.networkDownloadBytesPerSecond, AppTheme.network)
                rateCard("Upload", snap.networkUploadBytesPerSecond, AppTheme.cpu)
            }
            Panel(title: "Throughput", accessory: "3 min") {
                MultiSeriesChart(
                    points:
                        ChartSeries.custom(store.history, series: "Download") { $0.networkDownloadBytesPerSecond }
                        + ChartSeries.custom(store.history, series: "Upload") { $0.networkUploadBytesPerSecond },
                    colors: ["Download": AppTheme.network, "Upload": AppTheme.cpu],
                    maxValue: peak,
                    unitLabel: "B/s"
                )
                .frame(minHeight: 160)
                Text("The total counts Wi-Fi and Ethernet. A VPN stays in the list and is added only when those links are down, so the tunnel is not counted on top of the same packets. Bridge and peer links stay out of the total.")
                    .font(AppTheme.small)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Panel(title: "Interfaces", accessory: snap.networkInterfaces.isEmpty ? nil : "\(snap.networkInterfaces.count)") {
                if snap.networkInterfaces.isEmpty {
                    Text(store.hasSample ? "No active interfaces." : "Waiting for the first sample.")
                        .font(AppTheme.small)
                        .foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(snap.networkInterfaces) { interface in
                            interfaceRow(interface)
                        }
                    }
                }
            }
        }
    }

    private func rateCard(_ label: String, _ bytesPerSecond: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(AppTheme.micro)
                .foregroundStyle(AppTheme.muted)
            Text(MetricFormat.bytesPerSecond(bytesPerSecond))
                .font(AppTheme.hero)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.card)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.rule, lineWidth: 1))
        )
    }

    private func interfaceRow(_ interface: NetworkInterfaceSample) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(interface.displayName)
                        .font(AppTheme.small)
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                    Text(interface.name)
                        .font(AppTheme.micro)
                        .foregroundStyle(AppTheme.muted)
                    Text(interface.kind.title)
                        .font(AppTheme.micro)
                        .foregroundStyle(AppTheme.network)
                }
                Text(interface.addresses.isEmpty ? (interface.isUp ? "Up" : "Down") : interface.addresses.joined(separator: "  ·  "))
                    .font(AppTheme.micro)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text("↓ \(MetricFormat.bytesPerSecond(interface.downloadBytesPerSecond))")
                    .foregroundStyle(AppTheme.network)
                Text("↑ \(MetricFormat.bytesPerSecond(interface.uploadBytesPerSecond))")
                    .foregroundStyle(AppTheme.cpu)
            }
            .font(AppTheme.mono)
        }
        .padding(.vertical, 6)
    }
}
