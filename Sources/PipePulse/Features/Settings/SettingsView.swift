import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("refreshInterval") private var refreshInterval = RefreshInterval.oneMinute.rawValue
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("githubEnabled") private var githubEnabled = false
    @AppStorage("githubRepositories") private var githubRepositories = ""
    @AppStorage("gitlabEnabled") private var gitlabEnabled = false
    @AppStorage("gitlabRepositories") private var gitlabRepositories = ""
    @State private var githubToken = ""
    @State private var gitlabToken = ""
    @State private var integrationMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { handleDone() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider()

            Form {
                Section("Integrations") {
                    Toggle("Use GitHub Actions", isOn: $githubEnabled)
                        .toggleStyle(GreenToggleStyle())

                    if githubEnabled {
                        SecureField("GitHub personal access token", text: $githubToken)
                        TextField("Repositories", text: $githubRepositories, axis: .vertical)
                            .lineLimit(2...5)
                        Text("Required. Enter one repository per line, for example: acme/mobile-app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let integrationMessage {
                            Text(integrationMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    Toggle("Use GitLab CI/CD", isOn: $gitlabEnabled)
                        .toggleStyle(GreenToggleStyle())

                    if gitlabEnabled {
                        SecureField("GitLab personal access token", text: $gitlabToken)
                        TextField("Repositories", text: $gitlabRepositories, axis: .vertical)
                            .lineLimit(2...5)
                        Text("Required. Use the full path, for example: group/project")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let integrationMessage {
                            Text(integrationMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    Toggle(isOn: .constant(false)) {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Xcode Cloud")
                                Text("Coming soon")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: CIProvider.xcodeCloud.systemImage)
                        }
                    }
                    .disabled(true)
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
                gitlabToken = try KeychainStore().read(for: "gitlab-ci") ?? ""
            } catch {
                integrationMessage = "Could not read the saved token from Keychain."
            }
        }
    }

    private func handleDone() {
        guard githubEnabled || gitlabEnabled else {
            integrationMessage = nil
            appState.isShowingSettings = false
            return
        }

        do {
            if githubEnabled {
                let token = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
                let repositories = parseRepositories(githubRepositories)
                guard !token.isEmpty else {
                    integrationMessage = "Enter a GitHub token first."
                    return
                }
                guard !repositories.isEmpty else {
                    integrationMessage = "Add at least one GitHub repository."
                    return
                }
                try KeychainStore().save(token, for: "github-actions")
                githubRepositories = repositories.joined(separator: "\n")
            }

            if gitlabEnabled {
                let token = gitlabToken.trimmingCharacters(in: .whitespacesAndNewlines)
                let repositories = parseRepositories(gitlabRepositories)
                guard !token.isEmpty else {
                    integrationMessage = "Enter a GitLab token first."
                    return
                }
                guard !repositories.isEmpty else {
                    integrationMessage = "Add at least one GitLab repository."
                    return
                }
                try KeychainStore().save(token, for: "gitlab-ci")
                gitlabRepositories = repositories.joined(separator: "\n")
            }

            integrationMessage = nil
            Task { await appState.refresh() }
            appState.isShowingSettings = false
        } catch {
            integrationMessage = error.localizedDescription
        }
    }

    private func parseRepositories(_ value: String) -> [String] {
        value
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
