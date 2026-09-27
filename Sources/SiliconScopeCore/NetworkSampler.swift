import Darwin
import Foundation
import SystemConfiguration

final class NetworkSampler {
    private struct Counters {
        var bytesIn: UInt64
        var bytesOut: UInt64
    }

    private var previous: [String: Counters] = [:]
    private var previousTime: Date?
    private var descriptions: [String: Description] = [:]
    private var addresses: [String: [String]] = [:]
    private var describedNames: Set<String> = []
    private var describedAt = Date.distantPast

    func sample() -> NetworkSample {
        let now = Date()
        let elapsed = previousTime.map { now.timeIntervalSince($0) } ?? 0
        let raw = Self.readCounters()
        let names = Set(raw.map(\.name))
        if names != describedNames || now.timeIntervalSince(describedAt) >= 3 {
            descriptions = Self.interfaceDescriptions()
            addresses = Self.addressesByName()
            describedNames = names
            describedAt = now
        }

        var next: [String: Counters] = [:]
        var interfaces: [NetworkInterfaceSample] = []
        for entry in raw where !entry.name.hasPrefix("lo") {
            next[entry.name] = Counters(bytesIn: entry.bytesIn, bytesOut: entry.bytesOut)
            let description = descriptions[entry.name]
            let kind = description?.kind ?? Self.kind(forName: entry.name)
            let down: Double
            let up: Double
            if elapsed > 0.05, let old = previous[entry.name] {
                down = MetricMath.counterRate(current: entry.bytesIn, previous: old.bytesIn, elapsed: elapsed)
                up = MetricMath.counterRate(current: entry.bytesOut, previous: old.bytesOut, elapsed: elapsed)
            } else {
                down = 0
                up = 0
            }
            let flags = entry.flags
            let isUp = (flags & Int(IFF_UP)) != 0
            let isRunning = (flags & Int(IFF_RUNNING)) != 0
            let interfaceAddresses = addresses[entry.name] ?? []
            let carriesTraffic = down > 0 || up > 0
            let visible = kind == .wifi || kind == .ethernet || !interfaceAddresses.isEmpty || carriesTraffic
            guard (isUp || carriesTraffic), visible else { continue }
            interfaces.append(NetworkInterfaceSample(
                id: entry.name,
                name: entry.name,
                displayName: description?.displayName ?? kind.title,
                kind: kind,
                isUp: isRunning,
                addresses: interfaceAddresses,
                downloadBytesPerSecond: down,
                uploadBytesPerSecond: up
            ))
        }
        previous = next
        previousTime = now

        interfaces.sort { lhs, rhs in
            let lhsRank = lhs.kind.sortRank
            let rhsRank = rhs.kind.sortRank
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            let lhsRate = lhs.downloadBytesPerSecond + lhs.uploadBytesPerSecond
            let rhsRate = rhs.downloadBytesPerSecond + rhs.uploadBytesPerSecond
            if lhsRate != rhsRate { return lhsRate > rhsRate }
            return lhs.name < rhs.name
        }

        let totals = interfaces.networkTotals()
        return NetworkSample(
            interfaces: interfaces,
            downloadBytesPerSecond: totals.downloadBytesPerSecond,
            uploadBytesPerSecond: totals.uploadBytesPerSecond
        )
    }

    private struct RawInterface {
        var name: String
        var flags: Int
        var bytesIn: UInt64
        var bytesOut: UInt64
    }

    private struct Description {
        var displayName: String
        var kind: NetworkKind
    }

    private static func readCounters() -> [RawInterface] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        // The list can grow between the size query and the read. One retry covers that.
        for _ in 0..<2 {
            var length = 0
            guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return [] }
            var buffer = [UInt8](repeating: 0, count: length)
            let status = buffer.withUnsafeMutableBytes { raw -> Int32 in
                sysctl(&mib, 6, raw.baseAddress, &length, nil, 0)
            }
            if status == 0 {
                return parseInterfaces(buffer, length: length)
            }
            if errno != ENOMEM { return [] }
        }
        return []
    }

    /// Route messages are only 4-byte aligned. Loading `if_msghdr2` directly traps on arm64 and would stop every sample, not just the network page.
    private static func parseInterfaces(_ buffer: [UInt8], length: Int) -> [RawInterface] {
        let count = min(length, buffer.count)
        var result: [RawInterface] = []
        var offset = 0
        while offset + MemoryLayout<if_msghdr>.size <= count {
            guard let header = load(if_msghdr.self, from: buffer, at: offset) else { break }
            let step = Int(header.ifm_msglen)
            guard step > 0 else { break }
            if header.ifm_type == RTM_IFINFO2,
               offset + MemoryLayout<if_msghdr2>.size <= count,
               let info = load(if_msghdr2.self, from: buffer, at: offset) {
                var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                if if_indextoname(UInt32(info.ifm_index), &nameBuffer) != nil {
                    let name = String(cString: nameBuffer)
                    if !name.isEmpty {
                        result.append(RawInterface(
                            name: name,
                            flags: Int(info.ifm_flags),
                            bytesIn: info.ifm_data.ifi_ibytes,
                            bytesOut: info.ifm_data.ifi_obytes
                        ))
                    }
                }
            }
            offset += step
        }
        return result
    }

    private static func load<T>(_ type: T.Type, from buffer: [UInt8], at offset: Int) -> T? {
        let size = MemoryLayout<T>.size
        guard offset >= 0, offset + size <= buffer.count else { return nil }
        let aligned = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<T>.alignment)
        defer { aligned.deallocate() }
        var copied = false
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            aligned.copyMemory(from: base.advanced(by: offset), byteCount: size)
            copied = true
        }
        guard copied else { return nil }
        return aligned.load(as: T.self)
    }

    private static func addressesByName() -> [String: [String]] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [:] }
        defer { freeifaddrs(first) }
        var result: [String: [String]] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let entry = current.pointee
            cursor = entry.ifa_next
            guard let address = entry.ifa_addr else { continue }
            let family = address.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(address.pointee.sa_len)
            guard getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            var text = String(cString: host)
            if let zone = text.firstIndex(of: "%") {
                text = String(text[..<zone])
            }
            guard !text.isEmpty, text != "0.0.0.0", !text.hasPrefix("fe80:") else { continue }
            let name = String(cString: entry.ifa_name)
            var list = result[name] ?? []
            if !list.contains(text) {
                if family == UInt8(AF_INET) {
                    list.insert(text, at: 0)
                } else if list.count < 2 {
                    list.append(text)
                }
            }
            result[name] = Array(list.prefix(2))
        }
        return result
    }

    private static func interfaceDescriptions() -> [String: Description] {
        let copied = SCNetworkInterfaceCopyAll() as NSArray
        var result: [String: Description] = [:]
        for case let interface as SCNetworkInterface in copied {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String?, !bsd.isEmpty else { continue }
            let type = (SCNetworkInterfaceGetInterfaceType(interface) as String?) ?? ""
            let localized = (SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?) ?? ""
            let kind = kind(forType: type, name: bsd)
            let display = localized.isEmpty ? kind.title : localized
            result[bsd] = Description(displayName: display, kind: kind)
        }
        return result
    }

    private static func kind(forType type: String, name: String) -> NetworkKind {
        switch type {
        case "IEEE80211": return .wifi
        case "Ethernet": return .ethernet
        case "Bridge": return .bridge
        case "PPP", "VPN", "IPSec", "6to4": return .vpn
        default: return kind(forName: name)
        }
    }

    private static func kind(forName name: String) -> NetworkKind {
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") { return .vpn }
        if name.hasPrefix("bridge") { return .bridge }
        if name.hasPrefix("en") { return .ethernet }
        return .other
    }
}

private extension NetworkKind {
    var sortRank: Int {
        switch self {
        case .wifi: return 0
        case .ethernet: return 1
        case .vpn: return 2
        case .bridge: return 3
        case .other: return 4
        }
    }
}
