import SwiftUI
import AppKit

@main
struct PipePulseApp: App {
    @NSApplicationDelegateAdaptor(PipePulseAppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class PipePulseAppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var statusController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let state = AppState(notificationService: MacNotificationService())
        appState = state
        statusController = MenuBarController(appState: state)
        state.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.stopMonitoring()
        statusController?.shutdown()
    }
}

struct RootView: View {
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
    }
}
