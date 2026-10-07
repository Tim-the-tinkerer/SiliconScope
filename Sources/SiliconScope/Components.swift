import Charts
import SiliconScopeCore
import SwiftUI

struct Panel<Content: View>: View {
    var title: String
    var accessory: String? = nil
    var quality: MetricQuality? = nil
    var expands: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased())
                    .font(AppTheme.micro)
                    .foregroundStyle(AppTheme.muted)
                    .tracking(0.8)
                if let quality {
                    QualityBadge(quality: quality)
                }
                Spacer()
                if let accessory {
                    Text(accessory)
                        .font(AppTheme.mono)
                        .foregroundStyle(AppTheme.muted)
                }
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: expands ? .infinity : nil, alignment: .top)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: expands ? .infinity : nil, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.rule, lineWidth: 1)
        )
    }
}

struct StatCell: View {
    var label: String
    var value: String
    var color: Color = AppTheme.ink
    var quality: MetricQuality? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(label.uppercased())
                    .font(AppTheme.micro)
                    .foregroundStyle(AppTheme.muted)
                    .tracking(0.6)
                if let quality {
                    QualityBadge(quality: quality)
                }
            }
            Text(value)
                .font(AppTheme.mono)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct QualityBadge: View {
    var quality: MetricQuality

    var body: some View {
        Text(quality.title.uppercased())
            .font(AppTheme.micro)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.16)))
    }

    private var tint: Color {
        switch quality {
        case .measured: return AppTheme.ok
        case .estimated: return AppTheme.warn
        case .partial: return AppTheme.power
        case .unavailable: return AppTheme.muted
        }
    }
}

struct RingGauge: View {
    var progress: Double
    var color: Color
    var label: String
    var detail: String
    var estimated: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(AppTheme.faint, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: MetricMath.clamp01(progress))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(estimated
                     ? MetricFormat.estimatedPercent(progress, digits: 0)
                     : MetricFormat.percent(progress, digits: 0))
                    .font(.system(size: estimated ? 11 : 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
            }
            .frame(width: 62, height: 62)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AppTheme.small)
                    .foregroundStyle(AppTheme.muted)
                Text(detail)
                    .font(AppTheme.section)
                    .foregroundStyle(AppTheme.ink)
            }
            Spacer(minLength: 0)
        }
    }
}

struct HistoryLine: Identifiable {
    var id: String
    var date: Date
    var value: Double
    var series: String
}

struct AreaHistoryChart: View {
    var points: [HistoryLine]
    var color: Color
    var maxValue: Double
    var unitLabel: String = ""

    var body: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Time", point.date),
                y: .value(unitLabel.isEmpty ? "Value" : unitLabel, point.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [color.opacity(0.45), color.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)
            LineMark(
                x: .value("Time", point.date),
                y: .value(unitLabel.isEmpty ? "Value" : unitLabel, point.value)
            )
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...max(maxValue, 0.001))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(AppTheme.rule)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(axisLabel(number))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(AppTheme.muted)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background(AppTheme.panel.opacity(0.35))
        }
    }

    private func axisLabel(_ value: Double) -> String {
        if unitLabel.lowercased().contains("watt") {
            if maxValue < 1 {
                return String(format: "%.0f mW", value * 1000)
            }
            return String(format: "%.1f W", value)
        }
        if maxValue <= 1.01 {
            return String(format: "%.0f%%", value * 100)
        }
        if maxValue <= 40 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.0f", value)
    }
}

struct MultiSeriesChart: View {
    var points: [HistoryLine]
    var colors: [String: Color]
    var maxValue: Double
    var unitLabel: String = ""

    var body: some View {
        let order = seriesOrder
        Chart(points) { point in
            LineMark(
                x: .value("Time", point.date),
                y: .value("Value", point.value)
            )
            .foregroundStyle(by: .value("Series", point.series))
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 1.7, lineCap: .round))
        }
        .chartForegroundStyleScale(domain: order, range: order.map { colors[$0] ?? AppTheme.muted })
        .chartYScale(domain: 0...max(maxValue, 0.001))
        .chartXAxis(.hidden)
        .chartLegend(position: .top, alignment: .leading, spacing: 8)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(AppTheme.rule)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(axisLabel(number))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(AppTheme.muted)
                    }
                }
            }
        }
    }

    /// First-seen order, which is the order the caller built the series. Dictionary key order would reshuffle the legend and the colors.
    private var seriesOrder: [String] {
        var order: [String] = []
        var seen = Set<String>()
        for point in points where seen.insert(point.series).inserted {
            order.append(point.series)
        }
        if !order.isEmpty { return order }
        return colors.keys.sorted()
    }

    private func axisLabel(_ value: Double) -> String {
        if unitLabel.lowercased().contains("watt") {
            if maxValue < 1 {
                return String(format: "%.0f mW", value * 1000)
            }
            return String(format: "%.1f W", value)
        }
        if unitLabel == "B/s" {
            return MetricFormat.bytesPerSecond(value)
        }
        if maxValue <= 1.01 {
            return String(format: "%.0f%%", value * 100)
        }
        return String(format: "%.1f", value)
    }
}

struct PressureHistoryChart: View {
    var history: [Snapshot]

    private struct Point: Identifiable {
        var id: String
        var date: Date
        var level: Double
        var name: String
    }

    private var points: [Point] {
        history.enumerated().map { index, snapshot in
            let pressure = snapshot.memory.pressure
            return Point(
                id: "\(index)-\(snapshot.timestamp.timeIntervalSince1970)",
                date: snapshot.timestamp,
                level: pressure.chartLevel,
                name: pressure.title
            )
        }
    }

    var body: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Time", point.date),
                y: .value("Pressure", point.level)
            )
            .foregroundStyle(by: .value("Level", point.name))
            .interpolationMethod(.stepEnd)
            .opacity(0.35)

            LineMark(
                x: .value("Time", point.date),
                y: .value("Pressure", point.level)
            )
            .foregroundStyle(by: .value("Level", point.name))
            .interpolationMethod(.stepEnd)
            .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
        .chartForegroundStyleScale(domain: Self.levelNames, range: Self.levelColors)
        .chartLegend(.hidden)
        .chartYScale(domain: 0...4)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 1, 2, 3, 4]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(AppTheme.rule)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(Self.axisTitle(number))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(AppTheme.muted)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background(AppTheme.panel.opacity(0.35))
        }
    }

    private static let levelNames = ["Normal", "Warning", "Urgent", "Critical", "Unknown"]
    private static let levelColors = [AppTheme.ok, AppTheme.warn, AppTheme.danger, AppTheme.danger, AppTheme.muted]

    private static func axisTitle(_ level: Double) -> String {
        switch Int(level.rounded()) {
        case 1: return "Normal"
        case 2: return "Warn"
        case 3: return "Urgent"
        case 4: return "Crit"
        default: return "—"
        }
    }
}

struct CoreBarRow: View {
    var core: CoreSample
    var color: Color
    var clusterLabel: String

    private var title: String {
        if core.dieID > 0 {
            return "\(clusterLabel)\(core.dieID):\(core.coreID)"
        }
        return "\(clusterLabel)\(core.coreID)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(AppTheme.mono)
                .foregroundStyle(AppTheme.muted)
                .frame(width: 44, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.faint)
                    Capsule()
                        .fill(color.opacity(0.35))
                        .frame(width: barWidth(geo.size.width, core.activeRatio, minimum: 4))
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth(geo.size.width, core.scaledRatio, minimum: 3))
                }
            }
            .frame(height: 8)
            Text(MetricFormat.percent(core.activeRatio, digits: 0))
                .font(AppTheme.mono)
                .foregroundStyle(AppTheme.ink)
                .frame(width: 40, alignment: .trailing)
            Text(core.frequencyMHz > 0 ? MetricFormat.megahertz(core.frequencyMHz) : "—")
                .font(AppTheme.mono)
                .foregroundStyle(AppTheme.muted)
                .frame(width: 72, alignment: .trailing)
        }
    }

    /// A core at rest draws no bar. A tiny non-zero share still gets a visible stub.
    private func barWidth(_ full: CGFloat, _ ratio: Double, minimum: CGFloat) -> CGFloat {
        guard ratio > 0 else { return 0 }
        return max(minimum, full * ratio)
    }
}

struct MemoryDonut: View {
    var memory: MemorySample

    var body: some View {
        let slices: [(String, Double, Color)] = [
            ("App", Double(memory.appBytes), AppTheme.cpu),
            ("Wired", Double(memory.wiredBytes), AppTheme.power),
            ("Compressed", Double(memory.compressedBytes), AppTheme.ane),
            ("Cached", Double(memory.cachedFilesBytes), AppTheme.memory),
            ("Free", Double(memory.freeBytes), AppTheme.faint),
        ]
        let total = max(slices.reduce(0) { $0 + $1.1 }, 1)

        HStack(spacing: 18) {
            Canvas { context, size in
                let side = min(size.width, size.height)
                let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side).insetBy(dx: 8, dy: 8)
                var start = Angle.degrees(-90)
                for slice in slices where slice.1 > 0 {
                    let amount = Angle.degrees(360 * slice.1 / total)
                    var path = Path()
                    path.addArc(
                        center: CGPoint(x: rect.midX, y: rect.midY),
                        radius: min(rect.width, rect.height) / 2,
                        startAngle: start,
                        endAngle: start + amount,
                        clockwise: false
                    )
                    context.stroke(path, with: .color(slice.2), lineWidth: 14)
                    start += amount
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 220, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(slices, id: \.0) { slice in
                    HStack(spacing: 8) {
                        Circle().fill(slice.2).frame(width: 7, height: 7)
                        Text(slice.0)
                            .font(AppTheme.small)
                            .foregroundStyle(AppTheme.muted)
                        Spacer()
                        Text(MetricFormat.bytes(UInt64(slice.1)))
                            .font(AppTheme.mono)
                            .foregroundStyle(AppTheme.ink)
                    }
                }
            }
        }
    }
}

enum ChartSeries {
    static func ratio(_ history: [Snapshot], _ keyPath: KeyPath<Snapshot, Double>, series: String) -> [HistoryLine] {
        history.map {
            HistoryLine(id: "\(series)-\($0.timestamp.timeIntervalSince1970)", date: $0.timestamp, value: $0[keyPath: keyPath], series: series)
        }
    }

    static func watts(_ history: [Snapshot], _ keyPath: KeyPath<Snapshot, Double>, series: String) -> [HistoryLine] {
        ratio(history, keyPath, series: series)
    }

    static func custom(_ history: [Snapshot], series: String, _ value: (Snapshot) -> Double) -> [HistoryLine] {
        history.map {
            HistoryLine(id: "\(series)-\($0.timestamp.timeIntervalSince1970)", date: $0.timestamp, value: value($0), series: series)
        }
    }
}
