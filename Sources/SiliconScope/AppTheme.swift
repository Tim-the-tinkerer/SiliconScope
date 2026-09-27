import SiliconScopeCore
import SwiftUI

enum AppTheme {
    static let bg = Color(red: 0.055, green: 0.067, blue: 0.090)
    static let panel = Color(red: 0.078, green: 0.094, blue: 0.125)
    static let card = Color(red: 0.098, green: 0.118, blue: 0.157)
    static let cardHover = Color(red: 0.118, green: 0.141, blue: 0.188)
    static let ink = Color(red: 0.910, green: 0.929, blue: 0.969)
    static let muted = Color(red: 0.545, green: 0.584, blue: 0.659)
    static let faint = Color(red: 0.220, green: 0.255, blue: 0.325)
    static let rule = Color(red: 0.165, green: 0.196, blue: 0.255)

    static let cpu = Color(red: 0.302, green: 0.639, blue: 1.000)
    static let gpu = Color(red: 0.239, green: 0.863, blue: 0.592)
    static let memory = Color(red: 0.961, green: 0.757, blue: 0.298)
    static let ane = Color(red: 0.753, green: 0.518, blue: 0.988)
    static let power = Color(red: 1.000, green: 0.541, blue: 0.298)
    static let network = Color(red: 0.345, green: 0.816, blue: 0.910)
    static let disk = Color(red: 0.420, green: 0.780, blue: 0.700)
    static let ok = Color(red: 0.361, green: 0.820, blue: 0.537)
    static let warn = Color(red: 0.961, green: 0.620, blue: 0.243)
    static let danger = Color(red: 0.961, green: 0.341, blue: 0.357)

    static let title = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let section = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let value = Font.system(size: 28, weight: .semibold, design: .rounded)
    static let hero = Font.system(size: 34, weight: .bold, design: .rounded)
    static let body = Font.system(size: 13)
    static let small = Font.system(size: 11, weight: .medium)
    static let mono = Font.system(size: 12, design: .monospaced)
    static let micro = Font.system(size: 10, weight: .semibold, design: .rounded)

    static func pressureColor(_ pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: return ok
        case .warning: return warn
        case .urgent, .critical: return danger
        case .unknown: return muted
        }
    }
}

enum SidebarPage: String, CaseIterable, Identifiable {
    case overview
    case cpu
    case gpu
    case memory
    case ane
    case power
    case temperatures
    case network
    case disk
    case processes
    case hardware

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "Memory"
        case .ane: return "Neural Engine"
        case .power: return "Power"
        case .temperatures: return "Temperatures"
        case .network: return "Network"
        case .disk: return "Disk"
        case .processes: return "Processes"
        case .hardware: return "Hardware"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .cpu: return "cpu"
        case .gpu: return "display"
        case .memory: return "memorychip"
        case .ane: return "brain.head.profile"
        case .power: return "bolt.fill"
        case .temperatures: return "thermometer.medium"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .processes: return "list.bullet.rectangle"
        case .hardware: return "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .overview: return AppTheme.ink
        case .cpu: return AppTheme.cpu
        case .gpu: return AppTheme.gpu
        case .memory: return AppTheme.memory
        case .ane: return AppTheme.ane
        case .power: return AppTheme.power
        case .temperatures: return AppTheme.warn
        case .network: return AppTheme.network
        case .disk: return AppTheme.disk
        case .processes: return AppTheme.muted
        case .hardware: return AppTheme.muted
        }
    }
}
