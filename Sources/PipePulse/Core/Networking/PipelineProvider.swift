import Foundation

protocol PipelineProvider: Sendable {
    var provider: CIProvider { get }
    func fetchProjects() async throws -> [Project]
}

enum PipelineProviderError: LocalizedError {
    case invalidResponse
    case unauthorized
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The provider returned an invalid response."
        case .unauthorized: "The provider credentials are invalid or expired."
        case .unavailable: "The provider is temporarily unavailable."
        }
    }
}

// Kept small on purpose: concrete GitHub/GitLab clients can conform to this
// protocol without leaking API response types into the SwiftUI layer.
struct URLSessionPipelineTransport: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PipelineProviderError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200..<300: return data
        case 401, 403: throw PipelineProviderError.unauthorized
        default: throw PipelineProviderError.unavailable
        }
    }
}
