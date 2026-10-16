import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var dataSourceTitle = "Mock data"
    @Published private(set) var isLoading = false
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

    private var activeProvider: any PipelineProvider {
        guard defaults.bool(forKey: "githubEnabled") else { return provider }
        let token: String?
        do {
            token = try tokenStore.read(for: "github-actions")
        } catch {
            return provider
        }
        let repositories = (defaults.string(forKey: "githubRepositories") ?? "")
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let token, !token.isEmpty, !repositories.isEmpty else { return provider }
        return GitHubActionsProvider(accessToken: token, repositoryNames: repositories)
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
