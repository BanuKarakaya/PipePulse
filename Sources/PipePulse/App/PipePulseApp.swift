import SwiftUI
import AppKit

@main
struct PipePulseApp: App {
    @StateObject private var appState = AppState(
        provider: MockPipelineProvider(),
        notificationService: MacNotificationService()
    )
    @State private var isMenuPresented = false

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $isMenuPresented) {
            RootView()
                .environmentObject(appState)
        } label: {
            MenuBarStatusIcon()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("refreshInterval") private var refreshInterval = RefreshInterval.fiveMinutes.rawValue

    var body: some View {
        Group {
            if appState.isShowingOnboarding {
                OnboardingView()
            } else if appState.isShowingSettings {
                SettingsView()
            } else {
                DashboardView()
            }
        }
        .frame(width: 420, height: 570)
        .onAppear {
            appState.acknowledgeSuccessPulse()
        }
        .task(id: refreshInterval) {
            await refreshLoop()
        }
    }

    private func refreshLoop() async {
        await appState.refresh()
        guard refreshInterval > 0 else { return }
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(refreshInterval) * 1_000_000_000)
                await appState.refresh()
            } catch {
                return
            }
        }
    }
}

private struct MenuBarStatusIcon: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !appState.isSuccessPulseActive)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 0.9) / 0.9
            let pulse = 1.0 + 0.18 * (0.5 - 0.5 * cos(phase * 2.0 * .pi))

            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(appState.isSuccessPulseActive ? Color.green : Color.primary)
                .scaleEffect(appState.isSuccessPulseActive ? pulse : 1.0)
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel("PipePulse")
    }
}
