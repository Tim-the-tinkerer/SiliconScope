import AppKit
import SiliconScopeCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: MetricStore
    @StateObject private var login = LaunchAtLogin()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(AppTheme.title)
                .foregroundStyle(AppTheme.ink)

            card("Sampling") {
                settingRow(
                    "Polling interval",
                    "CPU, GPU, ANE, and power. Temperature still updates about every 3 s. Charts always keep three minutes."
                ) {
                    Picker("Polling interval", selection: $store.interval) {
                        ForEach(MetricStore.allowedIntervals, id: \.self) { value in
                            Text(label(for: value)).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 168)
                    .labelsHidden()
                }
            }

            card("Startup") {
                VStack(alignment: .leading, spacing: 14) {
                    settingRow(
                        "Open at login",
                        "Start Silicon Scope when you log in to this Mac."
                    ) {
                        Toggle("Open at login", isOn: loginBinding)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    if login.needsApproval {
                        HStack(spacing: 8) {
                            Text("Allow Silicon Scope in Login Items.")
                                .font(AppTheme.small)
                                .foregroundStyle(AppTheme.warn)
                            Button("Open Login Items") {
                                login.openLoginItems()
                            }
                            .controlSize(.small)
                        }
                    }

                    if let error = login.errorMessage {
                        Text(error)
                            .font(AppTheme.small)
                            .foregroundStyle(AppTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider().overlay(AppTheme.rule)

                    settingRow(
                        "Open window at launch",
                        "Off keeps Silicon Scope in the menu bar only, until you open the window."
                    ) {
                        Toggle("Open window at launch", isOn: $store.openWindowOnLaunch)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .disabled(!store.showMenuBar)
                }
            }

            card("Menu bar") {
                settingRow(
                    "Show menu bar extra",
                    "Live CPU, GPU, memory, and estimated ANE activity. When this is on, Silicon Scope stays out of the Dock."
                ) {
                    Toggle("Show menu bar extra", isOn: $store.showMenuBar)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 420)
        .background(AppTheme.bg)
        .preferredColorScheme(.dark)
        .onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            login.refresh()
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { login.isEnabled },
            set: { login.setEnabled($0) }
        )
    }

    private func label(for interval: TimeInterval) -> String {
        interval == 0.5 ? "0.5 s" : interval == 2 ? "2 s" : "1 s"
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(AppTheme.micro)
                .foregroundStyle(AppTheme.muted)
                .tracking(0.8)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.rule, lineWidth: 1)
        )
    }

    private func settingRow<Content: View>(
        _ title: String,
        _ caption: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTheme.body)
                    .foregroundStyle(AppTheme.ink)
                Text(caption)
                    .font(AppTheme.small)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control()
        }
    }
}
