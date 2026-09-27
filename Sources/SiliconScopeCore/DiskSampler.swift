import Darwin
import Foundation
import IOKit

public enum DiskSampler {
    public static func sample() -> DiskSample {
        autoreleasepool { readDrives() }
    }

    /// Decides which mounts belong on the Disk page. System, snapshot, and cryptex mounts stay off it.
    public static func visibility(mountPoint: String, source: String, fileSystem: String) -> DiskVisibility {
        let system = fileSystem.lowercased()
        if system == "devfs" || system == "autofs" || system == "bindfs" { return .hidden }
        if mountPoint.hasPrefix("/Volumes/.timemachine") || mountPoint == "/Volumes/Recovery" { return .hidden }
        if source.contains("com.apple.TimeMachine") || source.contains(".timemachine") { return .hidden }
        if mountPoint.contains("/com.apple.security.cryptexd/") { return .hidden }
        if system == "smbfs" || system == "cifs" || system == "nfs" || system == "afpfs" || system == "webdav" {
            return mountPoint.hasPrefix("/Volumes/") ? .network : .hidden
        }
        if mountPoint == "/" || mountPoint == "/System/Volumes/Data" { return .localVolume }
        if mountPoint.hasPrefix("/Volumes/") { return .localVolume }
        return .hidden
    }

    /// APFS registry names look like "Macintosh HD - Data@5". Snapshot objects keep the com.apple id.
    public static func cleanRegistryName(_ name: String) -> String {
        var text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix(" Media") {
            text.removeLast(" Media".count)
        }
        guard let mark = text.lastIndex(of: "@"), mark > text.startIndex else { return text }
        let suffix = text[text.index(after: mark)...]
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { return text }
        return String(text[..<mark]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func volumeTitle(registryName: String, mountedName: String, mountPoint: String) -> String {
        let cleaned = cleanRegistryName(registryName)
        let synthetic = cleaned.isEmpty
            || cleaned.contains("com.apple.")
            || cleaned.hasPrefix("disk")
            || cleaned == "AppleAPFSMedia"
            || cleaned == "Untitled"
        if !synthetic { return cleaned }
        if !mountedName.isEmpty { return mountedName }
        if mountPoint == "/" { return "Macintosh HD" }
        let leaf = URL(fileURLWithPath: mountPoint).lastPathComponent
        return leaf.isEmpty ? "Volume" : leaf
    }

    public static func fileSystemTitle(_ raw: String) -> String {
        switch raw.lowercased() {
        case "apfs": return "APFS"
        case "hfs": return "Mac OS Extended"
        case "msdos": return "MS-DOS"
        case "exfat": return "ExFAT"
        case "ntfs", "ufsd_ntfs", "tuxera_ntfs": return "NTFS"
        case "smbfs", "cifs": return "SMB"
        case "nfs": return "NFS"
        case "afpfs": return "AFP"
        case "webdav": return "WebDAV"
        case "udf": return "UDF"
        case "": return ""
        default: return raw.uppercased()
        }
    }

    private struct RawMedia {
        var entry: io_registry_entry_t
        var bsd: String
        var size: UInt64
        var whole: Bool
        var className: String
        var registryName: String
        var encrypted: Bool
    }

    private struct Ancestry {
        var outerWholeBSD: String = ""
        var containerBSD: String?
        var product = ""
        var vendor = ""
        var medium = ""
        var interconnect = ""
        var location = ""
        var virtual = false
    }

    fileprivate struct Mount {
        var source: String
        var mountPoint: String
        var fileSystem: String
        var readOnly: Bool
        var totalBytes: UInt64
        var availableBytes: UInt64
        var usedBytes: UInt64
        var bsdName: String
    }

    private static func readDrives() -> DiskSample {
        let media = readMedia()
        defer { for item in media { IOObjectRelease(item.entry) } }
        let byBSD = Dictionary(media.map { ($0.bsd, $0) }, uniquingKeysWith: { first, _ in first })

        var drives: [String: DiskDriveSample] = [:]
        for item in media where item.whole && item.className == "IOMedia" {
            let ancestry = ancestry(of: item.entry)
            let virtual = ancestry.virtual || ancestry.interconnect == "Virtual Interface"
            let kind: DiskKind = virtual ? .image : (ancestry.location == "External" ? .external : .internalDrive)
            let fallback = cleanRegistryName(item.registryName)
            drives[item.bsd] = DiskDriveSample(
                id: item.bsd,
                name: displayName(product: ancestry.product, vendor: ancestry.vendor, fallback: fallback),
                bsdName: item.bsd,
                kind: kind,
                protocolName: protocolTitle(ancestry.interconnect),
                solidState: solidState(ancestry.medium),
                sizeBytes: item.size,
                availableBytes: 0,
                volumes: []
            )
        }

        var countedContainers = Set<String>()
        for mount in readMounts() {
            switch visibility(mountPoint: mount.mountPoint, source: mount.source, fileSystem: mount.fileSystem) {
            case .hidden:
                continue
            case .network:
                drives[mount.mountPoint] = networkDrive(mount)
            case .localVolume:
                guard let item = byBSD[mount.bsdName] else { continue }
                let ancestors = ancestry(of: item.entry)
                let driveID = ancestors.outerWholeBSD.isEmpty ? mount.bsdName : ancestors.outerWholeBSD
                guard var drive = drives[driveID] else { continue }
                let container = ancestors.containerBSD ?? mount.bsdName
                if countedContainers.insert(driveID + "\t" + container).inserted {
                    drive.availableBytes += mount.availableBytes
                }
                let mountedName = mountedVolumeName(mount.mountPoint)
                drive.volumes.append(DiskVolumeSample(
                    id: mount.mountPoint,
                    name: volumeTitle(registryName: item.registryName, mountedName: mountedName, mountPoint: mount.mountPoint),
                    mountPoint: mount.mountPoint,
                    fileSystem: fileSystemTitle(mount.fileSystem),
                    usedBytes: mount.usedBytes,
                    readOnly: mount.readOnly,
                    encrypted: item.encrypted
                ))
                drives[driveID] = drive
            }
        }

        var listed = drives.values.filter { drive in
            drive.kind != .image || !drive.volumes.isEmpty
        }.map { drive -> DiskDriveSample in
            var copy = drive
            copy.availableBytes = min(copy.availableBytes, copy.sizeBytes)
            copy.volumes.sort(by: volumePrecedes)
            return copy
        }
        listed.sort(by: drivePrecedes)
        return DiskSample(drives: listed)
    }

    private static func networkDrive(_ mount: Mount) -> DiskDriveSample {
        let name = URL(fileURLWithPath: mount.mountPoint).lastPathComponent
        let title = name.isEmpty ? "Network" : name
        let volume = DiskVolumeSample(
            id: mount.mountPoint,
            name: title,
            mountPoint: mount.mountPoint,
            fileSystem: fileSystemTitle(mount.fileSystem),
            usedBytes: mount.usedBytes,
            readOnly: mount.readOnly,
            encrypted: false
        )
        return DiskDriveSample(
            id: "net:" + mount.mountPoint,
            name: title,
            bsdName: "",
            kind: .network,
            protocolName: fileSystemTitle(mount.fileSystem),
            solidState: nil,
            sizeBytes: mount.totalBytes,
            availableBytes: min(mount.availableBytes, mount.totalBytes),
            volumes: [volume]
        )
    }

    private static func readMedia() -> [RawMedia] {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOMedia"),
              IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var result: [RawMedia] = []
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            let current = entry
            entry = IOIteratorNext(iterator)
            guard let dict = properties(current),
                  let bsd = dict["BSD Name"] as? String,
                  !bsd.isEmpty else {
                IOObjectRelease(current)
                continue
            }
            result.append(RawMedia(
                entry: current,
                bsd: bsd,
                size: integer(dict["Size"]),
                whole: boolean(dict["Whole"]),
                className: objectClass(current),
                registryName: registryName(current),
                encrypted: boolean(dict["Encrypted"])
            ))
        }
        return result
    }

    private static func ancestry(of entry: io_registry_entry_t) -> Ancestry {
        var cursor = entry
        var owned: [io_registry_entry_t] = []
        defer { for item in owned { IOObjectRelease(item) } }
        var result = Ancestry()
        var steps = 0
        while steps < 32 {
            steps += 1
            let name = objectClass(cursor)
            if name.contains("HDIX") || name.contains("DiskImage") {
                result.virtual = true
            }
            if let dict = properties(cursor) {
                if name == "IOMedia", boolean(dict["Whole"]), let bsd = dict["BSD Name"] as? String, !bsd.isEmpty {
                    result.outerWholeBSD = bsd
                }
                if name == "AppleAPFSMedia", result.containerBSD == nil, let bsd = dict["BSD Name"] as? String, !bsd.isEmpty {
                    result.containerBSD = bsd
                }
                if let device = dict["Device Characteristics"] as? NSDictionary {
                    if result.product.isEmpty, let product = device["Product Name"] as? String {
                        result.product = product
                    }
                    if result.vendor.isEmpty, let vendor = device["Vendor Name"] as? String {
                        result.vendor = vendor
                    }
                    if result.medium.isEmpty, let medium = device["Medium Type"] as? String {
                        result.medium = medium
                    }
                }
                if let proto = dict["Protocol Characteristics"] as? NSDictionary {
                    if result.interconnect.isEmpty, let value = proto["Physical Interconnect"] as? String {
                        result.interconnect = value
                    }
                    if result.location.isEmpty, let value = proto["Physical Interconnect Location"] as? String {
                        result.location = value
                    }
                }
            }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(cursor, kIOServicePlane, &parent) == KERN_SUCCESS else { break }
            owned.append(parent)
            cursor = parent
        }
        return result
    }

    fileprivate static func readMounts() -> [Mount] {
        var buffer: UnsafeMutablePointer<statfs>?
        let count = getmntinfo_r_np(&buffer, MNT_NOWAIT)
        guard count > 0, let buffer else { return [] }
        defer { free(buffer) }

        var result: [Mount] = []
        result.reserveCapacity(Int(count))
        for index in 0..<Int(count) {
            let item = buffer[index]
            let mountPoint = cString(item.f_mntonname)
            let source = cString(item.f_mntfromname)
            let fileSystem = cString(item.f_fstypename)
            guard !mountPoint.isEmpty else { continue }
            let role = visibility(mountPoint: mountPoint, source: source, fileSystem: fileSystem)
            guard role != .hidden else { continue }
            let block = UInt64(item.f_bsize)
            let total = item.f_blocks * block
            let available = item.f_bavail * block
            let free = item.f_bfree * block
            let used = role == .localVolume ? (spaceUsed(at: mountPoint) ?? 0) : (total > free ? total - free : 0)
            result.append(Mount(
                source: source,
                mountPoint: mountPoint,
                fileSystem: fileSystem,
                readOnly: (item.f_flags & UInt32(MNT_RDONLY)) != 0,
                totalBytes: total,
                availableBytes: available,
                usedBytes: used,
                bsdName: bsdName(from: source)
            ))
        }
        return result
    }

    private static func spaceUsed(at path: String) -> UInt64? {
        var attributes = attrlist()
        attributes.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attributes.volattr = attrgroup_t(ATTR_VOL_SPACEUSED)
        var bytes = [UInt8](repeating: 0, count: 16)
        let result = bytes.withUnsafeMutableBytes { raw -> Int32 in
            getattrlist(path, &attributes, raw.baseAddress, raw.count, 0)
        }
        guard result == 0, bytes.count >= 12 else { return nil }
        // getattrlist packs the uint64 at offset 4, which is not a natural alignment.
        var used: UInt64 = 0
        withUnsafeMutableBytes(of: &used) { destination in
            destination.copyBytes(from: bytes[4..<12])
        }
        return used
    }

    private static func mountedVolumeName(_ path: String) -> String {
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeNameKey])
        return values?.volumeName ?? ""
    }

    private static func bsdName(from source: String) -> String {
        let text: String
        if let range = source.range(of: "/dev/") {
            text = String(source[range.upperBound...])
        } else {
            text = source
        }
        let token = text.split(whereSeparator: { $0 == "@" || $0 == "/" }).last.map(String.init) ?? text
        return token.hasPrefix("disk") ? token : ""
    }

    private static func displayName(product: String, vendor: String, fallback: String) -> String {
        let product = product.trimmingCharacters(in: .whitespacesAndNewlines)
        let vendor = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (product.isEmpty || product == "Disk Image") ? fallback : product
        let resolved = base.isEmpty ? "Disk" : base
        guard !vendor.isEmpty, resolved.range(of: vendor, options: .caseInsensitive) == nil else { return resolved }
        return "\(vendor) \(resolved)"
    }

    private static func protocolTitle(_ interconnect: String) -> String {
        switch interconnect {
        case "PCI-Express": return "PCI Express"
        case "Serial ATA": return "SATA"
        case "Virtual Interface": return "Disk Image"
        default: return interconnect
        }
    }

    private static func solidState(_ medium: String) -> Bool? {
        switch medium {
        case "Solid State": return true
        case "Rotational": return false
        default: return nil
        }
    }

    private static func drivePrecedes(_ lhs: DiskDriveSample, _ rhs: DiskDriveSample) -> Bool {
        let left = kindRank(lhs.kind)
        let right = kindRank(rhs.kind)
        if left != right { return left < right }
        let order = lhs.name.localizedStandardCompare(rhs.name)
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.bsdName < rhs.bsdName
    }

    private static func volumePrecedes(_ lhs: DiskVolumeSample, _ rhs: DiskVolumeSample) -> Bool {
        func rank(_ mount: String) -> Int {
            if mount == "/" { return 0 }
            if mount == "/System/Volumes/Data" { return 1 }
            return 2
        }
        let left = rank(lhs.mountPoint)
        let right = rank(rhs.mountPoint)
        if left != right { return left < right }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func kindRank(_ kind: DiskKind) -> Int {
        switch kind {
        case .internalDrive: return 0
        case .external: return 1
        case .image: return 2
        case .network: return 3
        }
    }

    private static func properties(_ entry: io_registry_entry_t) -> NSDictionary? {
        var raw: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &raw, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
        return raw?.takeRetainedValue()
    }

    private static func objectClass(_ entry: io_registry_entry_t) -> String {
        var name = [CChar](repeating: 0, count: 128)
        guard IOObjectGetClass(entry, &name) == KERN_SUCCESS else { return "" }
        return String(cString: name)
    }

    private static func registryName(_ entry: io_registry_entry_t) -> String {
        var name = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(entry, &name) == KERN_SUCCESS else { return "" }
        return String(cString: name)
    }

    private static func boolean(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }

    private static func integer(_ value: Any?) -> UInt64 {
        if let number = value as? NSNumber { return number.uint64Value }
        return 0
    }

    /// Mount identity only. Byte counts stay out of this so a file copy does not force a hardware rescan.
    fileprivate static func mountSignature(_ mounts: [Mount]) -> String {
        mounts.map { "\($0.mountPoint)\t\($0.source)\t\($0.readOnly)" }.joined(separator: "\n")
    }

    /// Writes the latest statfs numbers onto a cached drive list. One APFS container is counted once.
    fileprivate static func applyingUsage(_ drives: [DiskDriveSample], mounts: [Mount]) -> [DiskDriveSample] {
        guard !mounts.isEmpty else { return drives }
        let byMount = Dictionary(mounts.map { ($0.mountPoint, $0) }, uniquingKeysWith: { first, _ in first })
        return drives.map { drive in
            var copy = drive
            var seen = Set<String>()
            var available: UInt64 = 0
            var matched = false
            for index in copy.volumes.indices {
                guard let mount = byMount[copy.volumes[index].mountPoint] else { continue }
                matched = true
                copy.volumes[index].usedBytes = mount.usedBytes
                copy.volumes[index].readOnly = mount.readOnly
                let container = mount.bsdName.isEmpty ? mount.mountPoint : containerKey(mount.bsdName)
                if seen.insert(container).inserted {
                    available += mount.availableBytes
                }
            }
            if matched {
                copy.availableBytes = min(available, copy.sizeBytes)
            }
            return copy
        }
    }

    fileprivate static func containerKey(_ bsd: String) -> String {
        guard bsd.hasPrefix("disk") else { return bsd }
        var index = bsd.index(bsd.startIndex, offsetBy: 4)
        let start = index
        while index < bsd.endIndex, bsd[index].isNumber {
            index = bsd.index(after: index)
        }
        guard index > start else { return bsd }
        return String(bsd[..<index])
    }

    private static func cString<T>(_ value: T) -> String {
        withUnsafeBytes(of: value) { raw in
            guard let base = raw.bindMemory(to: CChar.self).baseAddress else { return "" }
            return String(cString: base)
        }
    }
}

/// Keeps the drive list from walking IOKit on every sample. Free space still follows each statfs read.
public final class DiskMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var drives: [DiskDriveSample] = []
    private var signature = ""
    private var refreshed = Date.distantPast
    /// Hardware identity changes slowly. Usage numbers are painted on from statfs every call.
    private let identityInterval: TimeInterval = 2

    public init() {}

    public func currentDrives() -> [DiskDriveSample] {
        let mounts = DiskSampler.readMounts()
        let signature = DiskSampler.mountSignature(mounts)
        let now = Date()
        lock.lock()
        let cached = drives
        let needsIdentity = cached.isEmpty || signature != self.signature || now.timeIntervalSince(refreshed) >= identityInterval
        lock.unlock()

        if needsIdentity {
            let fresh = DiskSampler.sample().drives
            lock.lock()
            drives = fresh
            self.signature = signature
            refreshed = now
            lock.unlock()
            return fresh
        }
        guard !mounts.isEmpty else { return cached }
        return DiskSampler.applyingUsage(cached, mounts: mounts)
    }
}
