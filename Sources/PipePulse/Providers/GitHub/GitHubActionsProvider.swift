import Foundation

struct GitHubActionsProvider: PipelineProvider {
    let provider: CIProvider = .githubActions
    let sourceTitle = "GitHub Actions"
    let accessToken: String
    let repositoryNames: [String]
    let session: URLSession

    init(accessToken: String, repositoryNames: [String], session: URLSession = .shared) {
        self.accessToken = accessToken
        self.repositoryNames = repositoryNames
        self.session = session
    }

    func fetchProjects() async throws -> [Project] {
        try await withThrowingTaskGroup(of: Project.self, returning: [Project].self) { group in
            for repositoryName in repositoryNames {
                group.addTask {
                    try await fetchProject(repositoryName: repositoryName)
                }
            }

            var projects: [Project] = []
            for try await project in group {
                projects.append(project)
            }
            return projects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    private func fetchProject(repositoryName: String) async throws -> Project {
        let parts = repositoryName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw PipelineProviderError.invalidResponse }

        let owner = parts[0]
        let name = parts[1]
        let endpoint = URL(string: "https://api.github.com/repos/\(owner)/\(name)/actions/runs?per_page=10")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PipelineProviderError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200..<300: break
        case 401, 403: throw PipelineProviderError.unauthorized
        case 404: throw PipelineProviderError.invalidResponse
        default: throw PipelineProviderError.unavailable
        }

        let decoded = try JSONDecoder().decode(WorkflowRunsResponse.self, from: data)
        let repository = Repository(
            id: UUID(),
            owner: owner,
            name: name,
            provider: .githubActions,
            url: URL(string: "https://github.com/\(owner)/\(name)")!
        )
        let pipelines = decoded.workflowRuns.map(\.pipeline)
        return Project(id: repository.id, repository: repository, pipelines: pipelines)
    }
}

private struct WorkflowRunsResponse: Decodable {
    let workflowRuns: [WorkflowRun]

    enum CodingKeys: String, CodingKey {
        case workflowRuns = "workflow_runs"
    }
}

private struct WorkflowRun: Decodable {
    let id: Int
    let name: String?
    let headBranch: String?
    let status: String
    let conclusion: String?
    let createdAt: String
    let runStartedAt: String?
    let updatedAt: String?
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion
        case headBranch = "head_branch"
        case createdAt = "created_at"
        case runStartedAt = "run_started_at"
        case updatedAt = "updated_at"
        case htmlURL = "html_url"
    }

    var pipeline: Pipeline {
        let startDate = Self.date(from: runStartedAt ?? createdAt) ?? .now
        let endDate = Self.date(from: updatedAt ?? createdAt)
        let duration = endDate.map { max(0, $0.timeIntervalSince(startDate)) }
        return Pipeline(
            id: UUID(uuidString: "00000000-0000-0000-0000-\(String(id).paddingLeft(toLength: 12, withPad: "0"))") ?? UUID(),
            name: name ?? "GitHub Actions run",
            branch: headBranch ?? "unknown",
            status: PipelineStatus(githubStatus: status, conclusion: conclusion),
            startedAt: startDate,
            duration: duration,
            webURL: htmlURL
        )
    }

    private static func date(from value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

private extension String {
    func paddingLeft(toLength length: Int, withPad character: Character) -> String {
        guard count < length else { return String(suffix(length)) }
        return String(repeating: String(character), count: length - count) + self
    }
}

extension PipelineStatus {
    init(githubStatus: String, conclusion: String?) {
        switch (githubStatus, conclusion) {
        case ("queued", _), ("requested", _), ("waiting", _), ("pending", _):
            self = .pending
        case ("in_progress", _), ("running", _):
            self = .running
        case (_, "success"):
            self = .success
        case (_, "failure"), (_, "timed_out"):
            self = .failed
        case (_, "cancelled"), (_, "skipped"):
            self = .canceled
        default:
            self = .pending
        }
    }
}
