import SwiftUI
import AppKit

@main
struct PipePulseApp: App {
    @StateObject private var appState: AppState

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let state = AppState(
            provider: MockPipelineProvider(),
            notificationService: MacNotificationService()
        )
        _appState = StateObject(wrappedValue: state)
        state.startMonitoring()
    }

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(true)) {
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
            appState.returnToDashboard()
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
