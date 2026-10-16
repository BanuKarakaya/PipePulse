import SwiftUI
import AppKit

@main
struct PipePulseApp: App {
    @StateObject private var appState = AppState(
        provider: MockPipelineProvider(),
        notificationService: MacNotificationService()
    )

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("PipePulse", systemImage: "waveform.path.ecg") {
            RootView()
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
