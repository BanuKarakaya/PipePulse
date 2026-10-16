import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 58, weight: .medium))
                .foregroundStyle(.tint)
                .padding(.bottom, 24)
            Text("Welcome to PipePulse")
                .font(.title2.weight(.bold))
            Text("See all your CI/CD pipelines at a glance, right from the menu bar.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 38)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 14) {
                OnboardingFeature(icon: "bolt.fill", title: "One focused dashboard", detail: "Track projects across your providers in one place.")
                OnboardingFeature(icon: "bell.fill", title: "Catch failures quickly", detail: "Get notified when a pipeline needs attention.")
                OnboardingFeature(icon: "lock.fill", title: "Secure by design", detail: "Provider tokens will be stored in macOS Keychain.")
            }
            .padding(.top, 28)
            .padding(.horizontal, 28)

            Spacer()
            Button("Get started") { appState.completeOnboarding() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 28)
        }
        .padding(20)
    }
}

private struct OnboardingFeature: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
