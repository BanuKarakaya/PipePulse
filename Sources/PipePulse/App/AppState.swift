import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var dataSourceTitle = "Mock data"
    @Published private(set) var isLoading = false
    @Published private(set) var isSuccessPulseActive = false
    @Published var errorMessage: String?
    @Published var selectedProjectID: UUID?
    @Published var isShowingSettings = false
    @Published var isShowingOnboarding: Bool

    private let provider: any PipelineProvider
    private let notificationService: any PipelineNotificationSending
    private let tokenStore: any SecureTokenStoring
    private let defaults: UserDefaults

    init(
        provider: any PipelineProvider = MockPipelineProvider(),
        notificationService: any PipelineNotificationSending = NoopPipelineNotificationService(),
        defaults: UserDefaults = .standard,
        tokenStore: any SecureTokenStoring = KeychainStore()
    ) {
        self.provider = provider
        self.notificationService = notificationService
        self.tokenStore = tokenStore
        self.defaults = defaults
        self.isShowingOnboarding = !defaults.bool(forKey: "hasCompletedOnboarding")
    }

    var selectedProject: Project? {
        projects.first { $0.id == selectedProjectID }
    }

    var successCount: Int { projects.compactMap(\.latestPipeline).filter { $0.status == .success }.count }
    var failedCount: Int { projects.compactMap(\.latestPipeline).filter { $0.status == .failed }.count }
    var runningCount: Int {
        projects.compactMap(\.latestPipeline).filter { $0.status == .running || $0.status == .pending }.count
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let selectedProvider = activeProvider
            let loadedProjects = try await selectedProvider.fetchProjects()
            if containsNewSuccess(in: loadedProjects, comparedWith: projects) {
                isSuccessPulseActive = true
            }
            dataSourceTitle = selectedProvider.sourceTitle
            projects = loadedProjects
            let notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
            if notificationsEnabled {
                for project in loadedProjects {
                    if let latest = project.latestPipeline {
                        await notificationService.notifyIfNeeded(for: latest)
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func acknowledgeSuccessPulse() {
        isSuccessPulseActive = false
    }

    private func containsNewSuccess(in updatedProjects: [Project], comparedWith previousProjects: [Project]) -> Bool {
        let previousByRepository = previousProjects.reduce(into: [String: Project]()) { projectsByKey, project in
            projectsByKey[repositoryKey(for: project)] = project
        }

        return updatedProjects.contains { updatedProject in
            guard
                let previousProject = previousByRepository[repositoryKey(for: updatedProject)],
                let previousPipeline = previousProject.latestPipeline,
                let updatedPipeline = updatedProject.latestPipeline,
                updatedPipeline.status == .success
            else {
                return false
            }

            return previousPipeline.status != .success || previousPipeline.webURL != updatedPipeline.webURL
        }
    }

    private func repositoryKey(for project: Project) -> String {
        "\(project.repository.provider.rawValue):\(project.repository.fullName)"
    }

    private var activeProvider: any PipelineProvider {
        var configuredProviders: [any PipelineProvider] = []

        if defaults.bool(forKey: "githubEnabled"),
           let token = token(for: "github-actions"),
           let repositories = repositories(for: "githubRepositories") {
            configuredProviders.append(
                GitHubActionsProvider(accessToken: token, repositoryNames: repositories)
            )
        }

        if defaults.bool(forKey: "gitlabEnabled"),
           let token = token(for: "gitlab-ci"),
           let repositories = repositories(for: "gitlabRepositories") {
            configuredProviders.append(
                GitLabCIProvider(accessToken: token, repositoryNames: repositories)
            )
        }

        guard !configuredProviders.isEmpty else { return provider }
        return CombinedPipelineProvider(providers: configuredProviders)
    }

    private func token(for account: String) -> String? {
        guard let token = try? tokenStore.read(for: account), !token.isEmpty else {
            return nil
        }
        return token
    }

    private func repositories(for key: String) -> [String]? {
        let values = (defaults.string(forKey: key) ?? "")
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values
    }

    func completeOnboarding() {
        defaults.set(true, forKey: "hasCompletedOnboarding")
        isShowingOnboarding = false
    }

    func resetOnboarding() {
        defaults.set(false, forKey: "hasCompletedOnboarding")
        isShowingOnboarding = true
    }
}
