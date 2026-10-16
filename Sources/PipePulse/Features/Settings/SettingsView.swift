import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("refreshInterval") private var refreshInterval = RefreshInterval.fiveMinutes.rawValue
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @State private var selectedProviders: Set<CIProvider> = [.githubActions, .gitLab]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { appState.isShowingSettings = false }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider()

            Form {
                Section("Integrations") {
                    ForEach(CIProvider.allCases, id: \.self) { provider in
                        Toggle(isOn: binding(for: provider)) {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(provider.title)
                                    Text(provider == .xcodeCloud ? "Coming soon" : "Connected with mock data")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: provider.systemImage)
                            }
                        }
                        .disabled(provider == .xcodeCloud)
                    }
                }

                Section("Monitoring") {
                    Picker("Refresh interval", selection: $refreshInterval) {
                        ForEach(RefreshInterval.allCases) { interval in
                            Text(interval.title).tag(interval.rawValue)
                        }
                    }
                    Toggle("Failure notifications", isOn: $notificationsEnabled)
                }

                Section("About") {
                    LabeledContent("Version", value: "0.1 MVP")
                    Button("Show onboarding again") { appState.resetOnboarding() }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 8)
        }
        .frame(width: 430, height: 500)
    }

    private func binding(for provider: CIProvider) -> Binding<Bool> {
        Binding(
            get: { selectedProviders.contains(provider) },
            set: { isSelected in
                if isSelected { selectedProviders.insert(provider) }
                else { selectedProviders.remove(provider) }
            }
        )
    }
}
