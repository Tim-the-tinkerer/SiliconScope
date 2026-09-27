import AppKit
import Darwin
import SiliconScopeCore
import SwiftUI

private enum ProcessColumn {
    case name
    case pid
    case cpu
    case memory
    case threads

    var ranking: ProcessRanking {
        switch self {
        case .name: return .name
        case .pid: return .pid
        case .cpu: return .cpu
        case .memory: return .memory
        case .threads: return .threads
        }
    }
}

private struct ProcessRow: View, Equatable {
    var process: ProcessSample
    var stripe: Bool
    var selected: Bool
    var select: () -> Void

    static func == (lhs: ProcessRow, rhs: ProcessRow) -> Bool {
        lhs.process == rhs.process && lhs.stripe == rhs.stripe && lhs.selected == rhs.selected
    }

    var body: some View {
        Button(action: select) {
            HStack {
                Text(process.name)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(process.pid)")
                    .frame(width: 70, alignment: .trailing)
                Text(MetricFormat.processCPU(process.cpuPercent))
                    .foregroundStyle(process.cpuPercent > 40 ? AppTheme.power : AppTheme.ink)
                    .frame(width: 70, alignment: .trailing)
                Text(MetricFormat.bytes(process.memoryBytes))
                    .frame(width: 90, alignment: .trailing)
                Text("\(process.threadCount)")
                    .frame(width: 70, alignment: .trailing)
            }
            .font(AppTheme.mono)
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(selected ? AppTheme.cpu.opacity(0.18) : (stripe ? AppTheme.panel.opacity(0.55) : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

struct ProcessesView: View {
    @EnvironmentObject var store: MetricStore
    @State private var sortColumn: ProcessColumn = .cpu
    @State private var ascending = false
    @State private var selectedPID: Int32?
    @State private var detail: ProcessDetail?
    @State private var detailToken = 0
    @State private var query = ""
    @State private var quitTarget: ProcessSample?
    @State private var quitForced = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var rows: [ProcessSample] {
        store.latest.processes
            .filter(matches)
            .sorted { lhs, rhs in
                ascending
                    ? Self.comesBefore(lhs, rhs, column: sortColumn)
                    : Self.comesBefore(rhs, lhs, column: sortColumn)
            }
    }

    var body: some View {
        let visible = rows
        GeometryReader { geo in
            HStack(alignment: .top, spacing: 12) {
                processList(visible)
                    .frame(maxWidth: .infinity, maxHeight: geo.size.height, alignment: .top)
                ProcessDetailView(detail: detail)
                    .frame(width: 360, alignment: .top)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .onAppear {
            store.setProcessRanking(sortColumn.ranking)
            store.setProcessSearch(query)
            refreshDetail()
        }
        .onChange(of: store.latest.timestamp) { _ in
            guard selectedPID != nil else { return }
            refreshDetail()
        }
        .onChange(of: query) { newValue in
            store.setProcessSearch(newValue)
        }
        .confirmationDialog(
            quitForced ? "Force quit \(quitTarget?.name ?? "this process")?" : "Quit \(quitTarget?.name ?? "this process")?",
            isPresented: Binding(
                get: { quitTarget != nil },
                set: { if !$0 { quitTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(quitForced ? "Force Quit" : "Quit", role: .destructive) {
                if let quitTarget {
                    signalProcess(quitTarget.pid, force: quitForced)
                }
                self.quitTarget = nil
            }
            Button("Cancel", role: .cancel) { quitTarget = nil }
        } message: {
            Text(quitForced
                 ? "Force quit stops it immediately. Unsaved work in that process is lost."
                 : "Quit asks the process to close. It can save its work and refuse.")
        }
    }

    @ViewBuilder
    private func processMenu(_ process: ProcessSample) -> some View {
        Button("Show Details") { select(process) }
        Divider()
        Button("Copy Name") { copy(process.name) }
        Button("Copy PID") { copy(String(process.pid)) }
        Button("Copy Path") { copyPath(process.pid) }
        Button("Reveal in Finder") { reveal(process.pid) }
        if process.pid > 1 {
            Divider()
            Button("Quit") { askToQuit(process, force: false) }
            Button("Force Quit") { askToQuit(process, force: true) }
        }
    }

    private func select(_ process: ProcessSample) {
        selectedPID = process.pid
        refreshDetail()
    }

    private func askToQuit(_ process: ProcessSample, force: Bool) {
        quitForced = force
        quitTarget = process
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyPath(_ pid: Int32) {
        guard let path = ProcessDetails.load(pid: pid)?.path, !path.isEmpty else { return }
        copy(path)
    }

    private func reveal(_ pid: Int32) {
        guard let path = ProcessDetails.load(pid: pid)?.path, !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func signalProcess(_ pid: Int32, force: Bool) {
        guard pid > 1 else { return }
        kill(pid, force ? SIGKILL : SIGTERM)
    }

    private func processList(_ visible: [ProcessSample]) -> some View {
        Panel(
            title: "Top processes",
            accessory: listAccessory(visible.count),
            quality: store.latest.confidence.processes,
            expands: true
        ) {
            VStack(spacing: 0) {
                searchField
                    .padding(.bottom, 10)
                HStack(spacing: 0) {
                    columnHeader(.name, "Name", leading: true)
                    columnHeader(.pid, "PID", width: 70)
                    columnHeader(.cpu, "CPU", width: 70)
                    columnHeader(.memory, "Memory", width: 90)
                    columnHeader(.threads, "Threads", width: 70)
                }
                .font(AppTheme.micro)
                .padding(.bottom, 8)

                if visible.isEmpty {
                    Text(emptyMessage)
                        .font(AppTheme.small)
                        .foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, proc in
                                ProcessRow(
                                    process: proc,
                                    stripe: index.isMultiple(of: 2),
                                    selected: selectedPID == proc.pid
                                ) {
                                    if selectedPID == proc.pid {
                                        selectedPID = nil
                                        detail = nil
                                    } else {
                                        selectedPID = proc.pid
                                        refreshDetail()
                                    }
                                }
                                .equatable()
                                .contextMenu { processMenu(proc) }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func listAccessory(_ shown: Int) -> String {
        if store.latest.confidence.processes != .measured { return "on this page only" }
        if trimmedQuery.isEmpty { return "\(shown) shown" }
        return "\(shown) matches"
    }

    private var emptyMessage: String {
        if !trimmedQuery.isEmpty { return "No processes match “\(trimmedQuery)”." }
        if store.latest.confidence.processes == .measured { return "Collecting process samples…" }
        return "Process lists are sampled only while this page is open. The next cycle will fill this table."
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.muted)
            TextField("Search name or PID", text: $query)
                .textFieldStyle(.plain)
                .font(AppTheme.body)
                .foregroundStyle(AppTheme.ink)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.muted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.rule, lineWidth: 1)
        )
    }

    private func matches(_ process: ProcessSample) -> Bool {
        let needle = trimmedQuery
        guard !needle.isEmpty else { return true }
        if process.name.localizedStandardContains(needle) { return true }
        return String(process.pid).contains(needle)
    }

    private func refreshDetail() {
        guard let pid = selectedPID else {
            detail = nil
            return
        }
        detailToken += 1
        let token = detailToken
        let cpu = store.latest.processes.first(where: { $0.pid == pid })?.cpuPercent
        Task.detached {
            let loaded = ProcessDetails.load(pid: pid, cpuPercent: cpu)
            await MainActor.run {
                guard token == detailToken else { return }
                detail = loaded
            }
        }
    }

    private func columnHeader(_ column: ProcessColumn, _ title: String, width: CGFloat? = nil, leading: Bool = false) -> some View {
        Button {
            if sortColumn == column {
                ascending.toggle()
            } else {
                sortColumn = column
                ascending = column == .name
            }
            store.setProcessRanking(column.ranking)
        } label: {
            HStack(spacing: 4) {
                if !leading { Spacer(minLength: 0) }
                Text(title)
                if sortColumn == column {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                if leading { Spacer(minLength: 0) }
            }
            .foregroundStyle(sortColumn == column ? AppTheme.ink : AppTheme.muted)
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
        }
        .buttonStyle(.plain)
        .frame(width: width, alignment: leading ? .leading : .trailing)
        .frame(maxWidth: leading ? .infinity : width, alignment: leading ? .leading : .trailing)
    }

    /// Ascending order. Equal keys fall through to a stable tie-break.
    private static func comesBefore(_ lhs: ProcessSample, _ rhs: ProcessSample, column: ProcessColumn) -> Bool {
        switch column {
        case .name:
            let compared = lhs.name.localizedStandardCompare(rhs.name)
            if compared == .orderedSame { return lhs.pid < rhs.pid }
            return compared == .orderedAscending
        case .pid:
            return lhs.pid < rhs.pid
        case .cpu:
            if lhs.cpuPercent != rhs.cpuPercent { return lhs.cpuPercent < rhs.cpuPercent }
            return lhs.pid < rhs.pid
        case .memory:
            if lhs.memoryBytes != rhs.memoryBytes { return lhs.memoryBytes < rhs.memoryBytes }
            return lhs.pid < rhs.pid
        case .threads:
            if lhs.threadCount != rhs.threadCount { return lhs.threadCount < rhs.threadCount }
            return lhs.pid < rhs.pid
        }
    }
}
