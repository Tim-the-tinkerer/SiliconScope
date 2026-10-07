import AppKit
import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.8"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "19"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 64, height: 64)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Silicon Scope")
                        .font(AppTheme.title)
                        .foregroundStyle(AppTheme.ink)
                    Text("Version \(version) (\(build))")
                        .font(AppTheme.mono)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
            }

            Text("A live monitor for the chip in this Mac. It samples CPU, GPU, unified memory, and the Apple Neural Engine without an administrator password, and it also shows temperatures, network traffic, and connected drives.")
                .font(AppTheme.body)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                line("CPU, GPU, and Neural Engine residency, frequency, and watts")
                line("Unified memory, pressure, and swap")
                line("Temperature sensors, grouped by what they measure")
                line("Download and upload, with each active network link")
                line("Internal, external, and network drives, including SMART data when a drive reports it")
            }

            Text("History charts keep about three minutes. The menu bar extra can show CPU, GPU, memory, and Neural Engine while the window is closed.")
                .font(AppTheme.small)
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Text("Copyright © 2026. All rights reserved.")
                .font(AppTheme.small)
                .foregroundStyle(AppTheme.muted)
        }
        .padding(24)
        .frame(width: 460, alignment: .topLeading)
        .background(AppTheme.bg)
    }

    private func line(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(AppTheme.disk)
                .frame(width: 6, height: 6)
            Text(text)
                .font(AppTheme.small)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
