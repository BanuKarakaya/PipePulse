import Foundation

/// Strips credentials before following a provider's signed log download redirect.
final class DiagnosticsRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    static func safeRedirect(from source: URL?, to request: URLRequest) -> URLRequest? {
        guard request.url?.scheme == "https" else { return nil }
        var redirected = request
        if source?.host != request.url?.host || source?.port != request.url?.port {
            redirected.setValue(nil, forHTTPHeaderField: "Authorization")
            redirected.setValue(nil, forHTTPHeaderField: "PRIVATE-TOKEN")
            redirected.setValue(nil, forHTTPHeaderField: "Cookie")
        }
        return redirected
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(Self.safeRedirect(from: response.url, to: request))
    }
}

struct DiagnosticsClient: Sendable {
    let session: URLSession
    let token: String
    let provider: CIProvider

    func get(_ url: URL, log: Bool = false) async throws -> (Data, HTTPURLResponse, Bool) {
        guard url.scheme == "https" else { throw DiagnosticsError.message("A secure HTTPS endpoint is required.") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue(log ? "text/plain" : "application/json", forHTTPHeaderField: "Accept")
        if provider == .githubActions {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        } else {
            request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        }
        // Reuse transport configuration (including test protocols), never disk caches,
        // ambient cookies, or stored credentials for sensitive diagnostic payloads.
        let configuration = session.configuration
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let privateSession = URLSession(configuration: configuration)
        defer { privateSession.invalidateAndCancel() }
        let (bytes, response) = try await privateSession.bytes(for: request, delegate: DiagnosticsRedirectDelegate())
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw PipelineProviderError.invalidResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw DiagnosticsError.message("Your token was rejected. Update it in Settings.")
        case 403:
            let permission = provider == .gitLab
                ? "GitLab needs Pipeline: Read for jobs and Job: Read for logs on this project."
                : "GitHub needs Actions: Read on this repository."
            throw DiagnosticsError.message("Access denied. \(permission) Check token permissions or try again later if rate-limited.")
        case 404: throw DiagnosticsError.message("This job or log is unavailable, expired, or not accessible with this token. Open it in the provider to check.")
        case 429: throw DiagnosticsError.message("The provider's rate limit was reached. Please try again later.")
        default: throw DiagnosticsError.message("The provider could not load these details (HTTP \(http.statusCode)). Try again later.")
        }
        let limit = log ? 1_048_576 : 4_194_304
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            if data.count == limit {
                if !log { throw DiagnosticsError.message("The job list is too large. Open the pipeline in the provider.") }
                return (data, http, true)
            }
            data.append(byte)
        }
        return (data, http, false)
    }
}
