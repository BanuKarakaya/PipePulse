import Foundation
import SwiftUI

private struct ProviderFetchResult: Sendable {
    let provider: CIProvider
    let sourceTitle: String
    let projects: [Project]?
    let errorMessage: String?
}

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
    private var monitoringTask: Task<Void, Never>?

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

    var successCount: Int { projects.flatMap(\.pipelines).filter { $0.status == .success }.count }
    var failedCount: Int { projects.flatMap(\.pipelines).filter { $0.status == .failed }.count }
    var runningCount: Int {
        projects.flatMap(\.pipelines).filter { $0.status == .running || $0.status == .pending }.count
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        let selectedProviders = activeProviders
        let results = await withTaskGroup(of: ProviderFetchResult.self) { group in
            for selectedProvider in selectedProviders {
                group.addTask {
                    do {
                        return ProviderFetchResult(
                            provider: selectedProvider.provider,
                            sourceTitle: selectedProvider.sourceTitle,
                            projects: try await selectedProvider.fetchProjects(),
                            errorMessage: nil
                        )
                    } catch {
                        return ProviderFetchResult(
                            provider: selectedProvider.provider,
                            sourceTitle: selectedProvider.sourceTitle,
                            projects: nil,
                            errorMessage: error.localizedDescription
                        )
                    }
                }
            }

            var results: [ProviderFetchResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        let successfulResults = results.filter { $0.projects != nil }
        let failedResults = results.filter { $0.projects == nil }
        let freshProjects = successfulResults.flatMap { $0.projects ?? [] }

        guard !successfulResults.isEmpty else {
            errorMessage = failedResults.map { "\($0.sourceTitle): \($0.errorMessage ?? "Unknown error")" }
                .joined(separator: " · ")
            return
        }

        let freshRepositoryKeys = Set(freshProjects.map(repositoryKey(for:)))
        let failedProviders = Set(failedResults.map(\.provider))
        let retainedStaleProjects = projects.filter {
            failedProviders.contains($0.repository.provider)
                && !freshRepositoryKeys.contains(repositoryKey(for: $0))
        }
        let updatedProjects = (freshProjects + retainedStaleProjects)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        if containsNewSuccess(in: updatedProjects, comparedWith: projects) {
            isSuccessPulseActive = true
        }
        dataSourceTitle = selectedProviders.map(\.sourceTitle).joined(separator: " + ")
        projects = updatedProjects
        if !failedResults.isEmpty {
            errorMessage = "Some data may be out of date — " + failedResults
                .map { "\($0.sourceTitle): \($0.errorMessage ?? "Unknown error")" }
                .joined(separator: " · ")
        }

        let notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
        if notificationsEnabled {
            for project in freshProjects {
                if let latest = project.latestPipeline {
                    await notificationService.notifyIfNeeded(for: latest)
                }
            }
        }
    }

    func startMonitoring() {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            var lastRefresh = Date()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }

                let interval = self.defaults.object(forKey: "refreshInterval") as? Int
                    ?? RefreshInterval.fiveMinutes.rawValue
                guard interval > 0, Date().timeIntervalSince(lastRefresh) >= Double(interval) else {
                    continue
                }
                await self.refresh()
                lastRefresh = Date()
            }
        }
    }

    func acknowledgeSuccessPulse() {
        isSuccessPulseActive = false
    }

    func returnToDashboard() {
        selectedProjectID = nil
        isShowingSettings = false
        acknowledgeSuccessPulse()
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

    private var activeProviders: [any PipelineProvider] {
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

        guard !configuredProviders.isEmpty else { return [provider] }
        return configuredProviders
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
