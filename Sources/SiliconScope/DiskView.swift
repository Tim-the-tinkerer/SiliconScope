import SiliconScopeCore
import SwiftUI

struct DiskView: View {
    @EnvironmentObject var store: MetricStore
    @State private var selectedID: String?
    @State private var detail: DiskDetail?
    @State private var detailToken = 0
    @State private var detailFetchedAt = Date.distantPast
    /// The BSD name of the read that is running. A second read waits until this one finishes.
    @State private var detailLoadingBSD: String?

    var body: some View {
        let drives = store.latest.drives
        let physical = drives.filter(\.kind.countsTowardCapacity)
        let capacity = physical.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        let free = physical.reduce(UInt64(0)) { $0 + $1.availableBytes }
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                summaryCard("Drives", drives.isEmpty ? "—" : "\(drives.count)", AppTheme.disk)
                summaryCard("Capacity", store.hasSample ? MetricFormat.bytes(capacity) : "—", AppTheme.ink)
                summaryCard("Free", store.hasSample ? MetricFormat.bytes(free) : "—", AppTheme.ok)
            }
            Panel(title: "Drives", accessory: drives.isEmpty ? nil : "\(drives.count)") {
                if drives.isEmpty {
                    Text(store.hasSample ? "No drives reported." : "Waiting for the first sample.")
                        .font(AppTheme.small)
                        .foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(drives.enumerated()), id: \.element.id) { index, drive in
                            driveBlock(drive)
                            if index < drives.count - 1 {
                                Divider().overlay(AppTheme.rule)
                            }
                        }
                    }
                }
            }
            Text("Capacity and free space count internal and external disks. Click a drive for storage details and SMART data when the drive reports it. Network shares stay in the list.")
                .font(AppTheme.small)
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: store.latest.timestamp) { _ in
            refreshDetail()
        }
    }

    private func driveBlock(_ drive: DiskDriveSample) -> some View {
        let selected = selectedID == drive.id
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                toggle(drive)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: selected ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppTheme.muted)
                                .frame(width: 10)
                            Text(drive.name)
                                .font(AppTheme.small)
                                .foregroundStyle(AppTheme.ink)
                                .lineLimit(1)
                            if !drive.bsdName.isEmpty {
                                Text(drive.bsdName)
                                    .font(AppTheme.micro)
                                    .foregroundStyle(AppTheme.muted)
                            }
                            Text(drive.kind.title)
                                .font(AppTheme.micro)
                                .foregroundStyle(AppTheme.disk)
                        }
                        Text(detailLine(drive))
                            .font(AppTheme.micro)
                            .foregroundStyle(AppTheme.muted)
                            .lineLimit(1)
                            .padding(.leading, 16)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(drive.volumes.isEmpty ? "Not mounted" : MetricFormat.bytes(drive.availableBytes))
                            .font(AppTheme.mono)
                            .foregroundStyle(drive.volumes.isEmpty ? AppTheme.muted : freeColor(drive))
                        if !drive.volumes.isEmpty {
                            Text("free of \(MetricFormat.bytes(drive.sizeBytes))")
                                .font(AppTheme.micro)
                                .foregroundStyle(AppTheme.muted)
                        } else {
                            Text(MetricFormat.bytes(drive.sizeBytes))
                                .font(AppTheme.micro)
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Storage details and SMART")
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.faint)
                    Capsule()
                        .fill(freeColor(drive))
                        .frame(width: max(0, geo.size.width * drive.usedRatio))
                }
            }
            .frame(height: 8)
            if !drive.volumes.isEmpty {
                VStack(spacing: 6) {
                    ForEach(drive.volumes) { volume in
                        volumeRow(volume)
                    }
                }
                .padding(.top, 2)
            }
            if selected {
                detailBlock(drive)
            }
        }
        .padding(selected ? 8 : 0)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? AppTheme.panel : Color.clear)
        )
    }

    @ViewBuilder
    private func detailBlock(_ drive: DiskDriveSample) -> some View {
        if drive.kind == .network {
            Text("SMART data is not available for a network share.")
                .font(AppTheme.small)
                .foregroundStyle(AppTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } else if let detail, detail.bsdName == drive.bsdName {
            VStack(alignment: .leading, spacing: 12) {
                if !detail.reported {
                    Text("Storage details could not be read.")
                        .font(AppTheme.small)
                        .foregroundStyle(AppTheme.muted)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                        if !detail.serialNumber.isEmpty { fact("Serial", detail.serialNumber) }
                        if !detail.revision.isEmpty { fact("Revision", detail.revision) }
                        if detail.blockSize > 0 { fact("Block size", "\(detail.blockSize) bytes") }
                        if !detail.partitionMap.isEmpty { fact("Partition map", detail.partitionMap) }
                        fact("SMART", detail.smartStatus.isEmpty ? "Not available" : detail.smartStatus, color: smartColor(detail.smartStatus))
                    }
                    if detail.attributes.isEmpty {
                        Text(detail.smartStatus.isEmpty
                             ? "This drive did not report SMART data."
                             : "SMART status is \(detail.smartStatus). This drive did not include an attribute table.")
                            .font(AppTheme.small)
                            .foregroundStyle(AppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                            ForEach(detail.attributes) { attribute in
                                fact(attribute.title, attribute.value, color: attributeColor(attribute))
                            }
                        }
                    }
                    if detail.hasActivity {
                        Text("ACTIVITY SINCE BOOT")
                            .font(AppTheme.micro)
                            .foregroundStyle(AppTheme.muted)
                            .tracking(0.6)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                            fact("Read", MetricFormat.bytes(detail.bytesRead))
                            fact("Written", MetricFormat.bytes(detail.bytesWritten))
                            fact("Read operations", grouped(detail.readOperations))
                            fact("Write operations", grouped(detail.writeOperations))
                            fact("Read errors", grouped(detail.readErrors), color: detail.readErrors > 0 ? AppTheme.danger : AppTheme.ink)
                            fact("Write errors", grouped(detail.writeErrors), color: detail.writeErrors > 0 ? AppTheme.danger : AppTheme.ink)
                            if detail.readRetries > 0 { fact("Read retries", grouped(detail.readRetries), color: AppTheme.warn) }
                            if detail.writeRetries > 0 { fact("Write retries", grouped(detail.writeRetries), color: AppTheme.warn) }
                        }
                    }
                }
            }
            .padding(.top, 4)
        } else {
            Text("Reading storage details…")
                .font(AppTheme.small)
                .foregroundStyle(AppTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
    }

    private func toggle(_ drive: DiskDriveSample) {
        if selectedID == drive.id {
            selectedID = nil
            detail = nil
            detailToken += 1
            return
        }
        selectedID = drive.id
        detail = nil
        detailFetchedAt = .distantPast
        refreshDetail(force: true)
    }

    private func refreshDetail(force: Bool = false) {
        guard let selectedID else { return }
        guard let drive = store.latest.drives.first(where: { $0.id == selectedID }), drive.kind != .network else { return }
        if detailLoadingBSD != nil { return }
        if !force, Date().timeIntervalSince(detailFetchedAt) < 5 { return }
        detailToken += 1
        let token = detailToken
        let bsdName = drive.bsdName
        detailLoadingBSD = bsdName
        detailFetchedAt = Date()
        Task.detached {
            let loaded = DiskDetails.load(bsdName: bsdName)
            await MainActor.run {
                detailLoadingBSD = nil
                guard token == detailToken else { return }
                let selected = self.selectedID.flatMap { id in
                    store.latest.drives.first { $0.id == id && $0.kind != .network }
                }
                guard let selected, selected.bsdName == bsdName else {
                    if let selected, selected.bsdName != bsdName {
                        detail = nil
                        detailFetchedAt = .distantPast
                        refreshDetail(force: true)
                    }
                    return
                }
                detail = loaded
            }
        }
    }

    private func fact(_ label: String, _ value: String, color: Color = AppTheme.ink) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(AppTheme.micro)
                .foregroundStyle(AppTheme.muted)
            Text(value)
                .font(AppTheme.mono)
                .foregroundStyle(color)
                .textSelection(.enabled)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func smartColor(_ status: String) -> Color {
        let text = status.lowercased()
        if text.contains("fail") { return AppTheme.danger }
        if text.contains("verified") { return AppTheme.ok }
        return AppTheme.muted
    }

    private func attributeColor(_ attribute: DiskSmartAttribute) -> Color {
        if attribute.id == "MEDIA_ERRORS" || attribute.id == "CRITICAL_WARNING" {
            if attribute.value != "0" && attribute.value != "None" { return AppTheme.warn }
        }
        if attribute.id == "PERCENTAGE_USED", let used = Int(attribute.value.dropLast()) , used >= 90 {
            return AppTheme.warn
        }
        return AppTheme.ink
    }

    private func grouped(_ value: UInt64) -> String {
        let digits = String(value)
        var parts: [String] = []
        var index = digits.endIndex
        while index > digits.startIndex {
            let start = digits.index(index, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
            parts.append(String(digits[start..<index]))
            index = start
        }
        return parts.reversed().joined(separator: ",")
    }

    private func volumeRow(_ volume: DiskVolumeSample) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(volume.name)
                        .font(AppTheme.small)
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                    Text(volumeTags(volume))
                        .font(AppTheme.micro)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                }
                Text(volume.mountPoint)
                    .font(AppTheme.micro)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(MetricFormat.bytes(volume.usedBytes))
                .font(AppTheme.mono)
                .foregroundStyle(AppTheme.ink)
        }
    }

    private func detailLine(_ drive: DiskDriveSample) -> String {
        var parts: [String] = []
        if let solid = drive.solidState {
            parts.append(solid ? "SSD" : "HDD")
        }
        if !drive.protocolName.isEmpty, drive.protocolName != drive.kind.title {
            parts.append(drive.protocolName)
        }
        if parts.isEmpty { return drive.kind.title }
        return parts.joined(separator: " · ")
    }

    private func volumeTags(_ volume: DiskVolumeSample) -> String {
        var parts = [volume.fileSystem]
        if volume.encrypted { parts.append("Encrypted") }
        if volume.readOnly { parts.append("Read-only") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func freeColor(_ drive: DiskDriveSample) -> Color {
        if drive.usedRatio >= 0.97 { return AppTheme.danger }
        if drive.usedRatio >= 0.90 { return AppTheme.warn }
        return AppTheme.disk
    }

    private func summaryCard(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(AppTheme.micro)
                .foregroundStyle(AppTheme.muted)
            Text(value)
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
}
