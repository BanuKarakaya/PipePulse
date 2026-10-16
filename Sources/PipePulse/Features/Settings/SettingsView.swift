import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("refreshInterval") private var refreshInterval = RefreshInterval.fiveMinutes.rawValue
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("githubEnabled") private var githubEnabled = false
    @AppStorage("githubRepositories") private var githubRepositories = ""
    @State private var githubToken = ""
    @State private var integrationMessage: String?
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
                    Toggle("Use GitHub Actions", isOn: $githubEnabled)
                        .toggleStyle(GreenToggleStyle())
                    SecureField("GitHub personal access token", text: $githubToken)
                    TextField("Repositories", text: $githubRepositories, axis: .vertical)
                        .lineLimit(2...5)
                    Text("Enter one repository per line, for example: acme/mobile-app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Save GitHub integration") {
                        saveGitHubIntegration()
                    }
                    if let integrationMessage {
                        Text(integrationMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(CIProvider.allCases.filter { $0 != .githubActions }, id: \.self) { provider in
                        Toggle(isOn: binding(for: provider)) {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(provider.title)
                                    Text(provider == .xcodeCloud ? "Coming soon" : "Available in a future update")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: provider.systemImage)
                            }
                        }
                        .disabled(true)
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
        .task {
            do {
                githubToken = try KeychainStore().read(for: "github-actions") ?? ""
            } catch {
                integrationMessage = "Could not read the saved token from Keychain."
            }
        }
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

    private func saveGitHubIntegration() {
        let token = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let repositories = githubRepositories
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !token.isEmpty else {
            integrationMessage = "Enter a GitHub token first."
            return
        }
        guard !repositories.isEmpty else {
            integrationMessage = "Add at least one repository."
            return
        }
        do {
            try KeychainStore().save(token, for: "github-actions")
            githubRepositories = repositories.joined(separator: "\n")
            githubEnabled = true
            integrationMessage = "Saved securely. Refreshing pipelines…"
            Task { await appState.refresh() }
        } catch {
            integrationMessage = error.localizedDescription
        }
    }
}

private struct GreenToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack {
                configuration.label
                Spacer()
                Capsule()
                    .fill(configuration.isOn ? Color.green : Color.gray.opacity(0.35))
                    .frame(width: 38, height: 22)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                            .padding(2)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}
