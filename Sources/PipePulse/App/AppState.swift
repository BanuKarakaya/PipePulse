import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedProjectID: UUID?
    @Published var isShowingSettings = false
    @Published var isShowingOnboarding: Bool

    private let provider: any PipelineProvider
    private let notificationService: any PipelineNotificationSending
    private let defaults: UserDefaults

    init(
        provider: any PipelineProvider = MockPipelineProvider(),
        notificationService: any PipelineNotificationSending = NoopPipelineNotificationService(),
        defaults: UserDefaults = .standard
    ) {
        self.provider = provider
        self.notificationService = notificationService
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
            let loadedProjects = try await provider.fetchProjects()
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

    func completeOnboarding() {
        defaults.set(true, forKey: "hasCompletedOnboarding")
        isShowingOnboarding = false
    }

    func resetOnboarding() {
        defaults.set(false, forKey: "hasCompletedOnboarding")
        isShowingOnboarding = true
    }
}
