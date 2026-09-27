import SiliconScopeCore
import SwiftUI

struct ProcessDetailView: View {
    var detail: ProcessDetail?

    var body: some View {
        Panel(title: "Process", accessory: detail.map { "PID \($0.pid)" }) {
            if let detail {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(detail.name)
                            .font(AppTheme.section)
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(1)
                        Text(detail.path.isEmpty ? "Path unavailable" : detail.path)
                            .font(AppTheme.small)
                            .foregroundStyle(AppTheme.muted)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                        fact("User", "\(detail.userName) (\(detail.userID))")
                        fact("Parent", parentLine(detail))
                        fact("Status", detail.status)
                        fact("Started", detail.started.formatted(date: .abbreviated, time: .standard))
                        fact("CPU", detail.cpuPercent.map(MetricFormat.processCPU) ?? "—")
                        fact("CPU time", "\(MetricFormat.duration(detail.userTime + detail.systemTime))")
                        fact("User time", MetricFormat.duration(detail.userTime))
                        fact("System time", MetricFormat.duration(detail.systemTime))
                        fact("Threads", "\(detail.runningThreads) running / \(detail.threadCount)")
                        fact("Priority", "\(detail.priority) · nice \(detail.nice)")
                        fact("Resident", MetricFormat.bytes(detail.residentBytes))
                        fact("Virtual", MetricFormat.bytes(detail.virtualBytes))
                        fact("Open files", "\(detail.openFiles)")
                        fact("Architecture", detail.is64Bit ? "64-bit" : "32-bit")
                        fact("Faults", "\(detail.faults)")
                        fact("Page-ins", "\(detail.pageins)")
                        fact("Copy-on-write", "\(detail.copyOnWriteFaults)")
                        fact("Context switches", "\(detail.contextSwitches)")
                        fact("Unix calls", "\(detail.unixCalls)")
                        fact("Mach calls", "\(detail.machCalls)")
                    }
                }
            } else {
                Text("Select a process to see its path, owner, parent, CPU time, and memory.")
                    .font(AppTheme.small)
                    .foregroundStyle(AppTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            }
        }
    }

    private func parentLine(_ detail: ProcessDetail) -> String {
        if detail.parentPID <= 0 { return "—" }
        if detail.parentName.isEmpty { return "\(detail.parentPID)" }
        return "\(detail.parentName) (\(detail.parentPID))"
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(AppTheme.micro)
                .foregroundStyle(AppTheme.muted)
            Text(value)
                .font(AppTheme.mono)
                .foregroundStyle(AppTheme.ink)
                .textSelection(.enabled)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
