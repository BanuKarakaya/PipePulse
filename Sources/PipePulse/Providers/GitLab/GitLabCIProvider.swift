import Foundation

struct GitLabCIProvider: PipelineProvider {
    let provider: CIProvider = .gitLab
    let sourceTitle = "GitLab CI/CD"
    let accessToken: String
    let repositoryNames: [String]
    let baseURL: URL
    let session: URLSession

    init(
        accessToken: String,
        repositoryNames: [String],
        baseURL: URL = URL(string: "https://gitlab.com")!,
        session: URLSession = .shared
    ) {
        self.accessToken = accessToken
        self.repositoryNames = repositoryNames
        self.baseURL = baseURL
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
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
        guard let encodedProject = repositoryName.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
            throw PipelineProviderError.invalidResponse
        }
        let endpoint = URL(string: "\(baseURL.absoluteString)/api/v4/projects/\(encodedProject)/pipelines?per_page=10&order_by=id&sort=desc")!
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = "GET"
        request.setValue(accessToken, forHTTPHeaderField: "PRIVATE-TOKEN")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

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

        let decoded = try JSONDecoder().decode([GitLabPipeline].self, from: data)
        let pathComponents = repositoryName.split(separator: "/")
        let repository = Repository(
            id: UUID(),
            owner: pathComponents.dropLast().joined(separator: "/"),
            name: pathComponents.last.map(String.init) ?? repositoryName,
            provider: .gitLab,
            url: URL(string: "\(baseURL.absoluteString)/\(repositoryName)")!
        )
        let pipelines = decoded.map { $0.pipeline(repositoryName: repositoryName) }
        return Project(id: repository.id, repository: repository, pipelines: pipelines)
    }
}

private struct GitLabPipeline: Decodable {
    let id: Int
    let status: String
    let ref: String?
    let createdAt: String?
    let startedAt: String?
    let finishedAt: String?
    let duration: TimeInterval?
    let webURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, status, ref, duration
        case createdAt = "created_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case webURL = "web_url"
    }

    func pipeline(repositoryName: String) -> Pipeline {
        let creationDate = Self.date(from: createdAt)
        let startDate = Self.date(from: startedAt) ?? creationDate ?? .now
        let endDate = Self.date(from: finishedAt)
        let measuredDuration = duration ?? endDate.map { max(0, $0.timeIntervalSince(startDate)) }
        return Pipeline(
            id: Self.stableUUID(for: id),
            name: "GitLab pipeline #\(id)",
            branch: ref ?? "unknown",
            status: PipelineStatus(gitLabStatus: status),
            startedAt: startDate,
            duration: measuredDuration,
            webURL: webURL ?? URL(string: "https://gitlab.com/\(repositoryName)/-/pipelines")!,
            createdAt: creationDate,
            remoteSequence: Int64(id)
        )
    }

    private static func stableUUID(for id: Int) -> UUID {
        let suffix = String(format: "%012d", id)
        return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)") ?? UUID()
    }

    private static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}

extension PipelineStatus {
    init(gitLabStatus: String) {
        switch gitLabStatus.lowercased() {
        case "created", "waiting_for_resource", "preparing", "pending", "manual":
            self = .pending
        case "running":
            self = .running
        case "success":
            self = .success
        case "failed":
            self = .failed
        case "canceled", "cancelled", "skipped":
            self = .canceled
        default:
            self = .pending
        }
    }
}
