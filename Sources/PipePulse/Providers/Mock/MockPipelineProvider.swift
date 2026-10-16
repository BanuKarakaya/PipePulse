import Foundation

struct MockPipelineProvider: PipelineProvider {
    let provider: CIProvider = .githubActions

    func fetchProjects() async throws -> [Project] {
        try await Task.sleep(for: .milliseconds(250))
        return Self.projects
    }

    private static let projects: [Project] = {
        let now = Date()
        let mobileRepository = Repository(
            id: UUID(uuidString: "7E5F1CFB-0A28-4F6C-8E5A-4C7CDA4F4A01")!,
            owner: "acme",
            name: "mobile-app",
            provider: .githubActions,
            url: URL(string: "https://github.com/acme/mobile-app")!
        )
        let apiRepository = Repository(
            id: UUID(uuidString: "7E5F1CFB-0A28-4F6C-8E5A-4C7CDA4F4A02")!,
            owner: "acme",
            name: "payments-api",
            provider: .gitLab,
            url: URL(string: "https://gitlab.com/acme/payments-api")!
        )
        let designRepository = Repository(
            id: UUID(uuidString: "7E5F1CFB-0A28-4F6C-8E5A-4C7CDA4F4A03")!,
            owner: "acme",
            name: "design-system",
            provider: .githubActions,
            url: URL(string: "https://github.com/acme/design-system")!
        )

        func pipeline(_ name: String, _ branch: String, _ status: PipelineStatus, _ minutesAgo: Int, _ duration: TimeInterval?, _ url: String) -> Pipeline {
            Pipeline(id: UUID(), name: name, branch: branch, status: status, startedAt: now.addingTimeInterval(-Double(minutesAgo * 60)), duration: duration, webURL: URL(string: url)!)
        }

        return [
            Project(id: mobileRepository.id, repository: mobileRepository, pipelines: [
                pipeline("Build and Test", "main", .success, 8, 142, "https://github.com/acme/mobile-app/actions"),
                pipeline("Build and Test", "feature/new-home", .running, 2, nil, "https://github.com/acme/mobile-app/actions"),
                pipeline("Build and Test", "release/2.4", .failed, 93, 81, "https://github.com/acme/mobile-app/actions")
            ]),
            Project(id: apiRepository.id, repository: apiRepository, pipelines: [
                pipeline("Deploy production", "main", .failed, 14, 64, "https://gitlab.com/acme/payments-api/-/pipelines"),
                pipeline("Test suite", "main", .success, 48, 214, "https://gitlab.com/acme/payments-api/-/pipelines"),
                pipeline("Security scan", "main", .pending, 55, nil, "https://gitlab.com/acme/payments-api/-/pipelines")
            ]),
            Project(id: designRepository.id, repository: designRepository, pipelines: [
                pipeline("Publish package", "main", .success, 31, 39, "https://github.com/acme/design-system/actions"),
                pipeline("Visual regression", "main", .canceled, 125, 17, "https://github.com/acme/design-system/actions")
            ])
        ]
    }()
}
