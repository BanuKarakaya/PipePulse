import Foundation

enum PipelineStatus: String, CaseIterable, Codable, Hashable, Sendable {
    case success
    case failed
    case running
    case pending
    case canceled

    var title: String {
        switch self {
        case .success: "Success"
        case .failed: "Failed"
        case .running: "Running"
        case .pending: "Pending"
        case .canceled: "Canceled"
        }
    }

    var systemImage: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .running: "arrow.triangle.2.circlepath.circle.fill"
        case .pending: "clock.fill"
        case .canceled: "minus.circle.fill"
        }
    }
}

enum CIProvider: String, CaseIterable, Codable, Hashable, Sendable {
    case githubActions
    case gitLab
    case xcodeCloud

    var title: String {
        switch self {
        case .githubActions: "GitHub Actions"
        case .gitLab: "GitLab CI/CD"
        case .xcodeCloud: "Xcode Cloud"
        }
    }

    var systemImage: String {
        switch self {
        case .githubActions: "chevron.left.forwardslash.chevron.right"
        case .gitLab: "shippingbox.fill"
        case .xcodeCloud: "cloud.fill"
        }
    }
}

struct Repository: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let owner: String
    let name: String
    let provider: CIProvider
    let url: URL

    var fullName: String { "\(owner)/\(name)" }
}

struct Pipeline: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let name: String
    let branch: String
    let status: PipelineStatus
    let startedAt: Date
    let createdAt: Date?
    let duration: TimeInterval?
    let webURL: URL

    init(
        id: UUID,
        name: String,
        branch: String,
        status: PipelineStatus,
        startedAt: Date,
        duration: TimeInterval?,
        webURL: URL,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.branch = branch
        self.status = status
        self.startedAt = startedAt
        self.createdAt = createdAt
        self.duration = duration
        self.webURL = webURL
    }

    var sortDate: Date { createdAt ?? startedAt }

    var durationText: String {
        guard let duration else { return status == .running ? "In progress" : "—" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }
}

struct Project: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let repository: Repository
    let pipelines: [Pipeline]

    var name: String { repository.name }
    var latestPipeline: Pipeline? { pipelines.max { $0.sortDate < $1.sortDate } }
}
