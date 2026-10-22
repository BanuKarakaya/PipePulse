import Foundation
import XCTest
@testable import PipePulse

private final class FixtureRegistry: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, [String: String], Data)
    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]
    func set(_ handler: Handler?, for id: String) { lock.lock(); defer { lock.unlock() }; handlers[id] = handler }
    func get(_ id: String) -> Handler? { lock.lock(); defer { lock.unlock() }; return handlers[id] }
}

private final class DiagnosticsURLProtocol: URLProtocol, @unchecked Sendable {
    static let registry = FixtureRegistry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let id = request.value(forHTTPHeaderField: "X-Test-ID"),
                  let handler = Self.registry.get(id) else { throw URLError(.badURL) }
            let (status, headers, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private final class FixtureSession {
    let id = UUID().uuidString
    let session: URLSession
    init(_ handler: @escaping FixtureRegistry.Handler) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiagnosticsURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Test-ID": id]
        session = URLSession(configuration: configuration)
        DiagnosticsURLProtocol.registry.set(handler, for: id)
    }
    deinit { session.invalidateAndCancel(); DiagnosticsURLProtocol.registry.set(nil, for: id) }
}

private func repository(_ provider: CIProvider = .gitLab) -> Repository {
    Repository(id: UUID(), owner: "team/subgroup", name: "repo", provider: provider, url: URL(string: "https://example.com/team/repo")!)
}

private func pipeline() -> Pipeline {
    Pipeline(id: UUID(), name: "Build", branch: "main", status: .failed, startedAt: .now, duration: 10,
             webURL: URL(string: "https://example.com/pipelines/42")!, remoteSequence: 42)
}

final class DiagnosticsTests: XCTestCase {
    func testGitLabJobsPaginationAndTrace() async throws {
        let fixture = FixtureSession { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "PRIVATE-TOKEN"), "test-secret")
            XCTAssertTrue(request.url!.absoluteString.contains("team%2Fsubgroup%2Frepo"))
            if request.url!.path.hasSuffix("/trace") {
                return (200, [:], Data("start\nERROR test failed test-secret\nend".utf8))
            }
            let second = request.url!.query!.contains("page=2")
            let id = second ? 2 : 1
            return (200, ["X-Next-Page": second ? "" : "2"], Data("""
            [{"id":\(id),"name":"test \(id)","stage":"test","status":"failed","failure_reason":"script_failure","web_url":"https://gitlab.com/jobs/\(id)"}]
            """.utf8))
        }
        let provider = GitLabCIProvider(accessToken: "test-secret", repositoryNames: [], session: fixture.session)
        let result = try await provider.failedJobs(repository: repository(), pipeline: pipeline())
        XCTAssertEqual(result.jobs.map(\.id), [1, 2])
        XCTAssertFalse(result.isTruncated)
        XCTAssertTrue(result.jobs[0].summary.contains("script failure"))
        let excerpt = try await provider.jobLog(repository: repository(), job: result.jobs[0])
        XCTAssertTrue(excerpt.matchedError)
        XCTAssertFalse(excerpt.text.contains("test-secret"))
        XCTAssertTrue(excerpt.text.contains("[REDACTED]"))
    }

    func testGitHubFiltersSuccessfulJobsAndIncludesFailedStep() async throws {
        let fixture = FixtureSession { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            XCTAssertTrue(request.url!.path.contains("/actions/runs/42/jobs"))
            XCTAssertTrue(request.url!.query!.contains("filter=latest"))
            return (200, [:], Data(#"{"total_count":2,"jobs":[{"id":3,"name":"Tests","conclusion":"failure","html_url":"https://github.com/jobs/3","steps":[{"name":"Unit tests","conclusion":"failure"}]},{"id":4,"name":"Build","conclusion":"success","html_url":"https://github.com/jobs/4"}]}"#.utf8))
        }
        let provider = GitHubActionsProvider(accessToken: "token", repositoryNames: [], session: fixture.session)
        let result = try await provider.failedJobs(repository: repository(.githubActions), pipeline: pipeline())
        XCTAssertEqual(result.jobs.map(\.id), [3])
        XCTAssertEqual(result.jobs.first?.summary, "Failed steps: Unit tests")
    }

    func testGitHubPaginationAndLimitAreExplicit() async throws {
        let fixture = FixtureSession { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let page = components.queryItems!.first { $0.name == "page" }!.value!
            return (200, [:], Data("""
            {"total_count":999,"jobs":[{"id":\(page),"name":"Test","conclusion":"timed_out","html_url":"https://github.com/jobs/\(page)"}]}
            """.utf8))
        }
        let provider = GitHubActionsProvider(accessToken: "token", repositoryNames: [], session: fixture.session)
        let result = try await provider.failedJobs(repository: repository(.githubActions), pipeline: pipeline())
        XCTAssertEqual(result.jobs.map(\.id), [1, 2, 3, 4, 5])
        XCTAssertTrue(result.isTruncated)
    }

    func testPermissionAndUnavailableErrors() async throws {
        for (code, expected) in [(401, "token"), (403, "Job: Read"), (404, "unavailable"), (429, "rate limit"), (500, "HTTP 500")] {
            let fixture = FixtureSession { _ in (code, [:], Data()) }
            let client = DiagnosticsClient(session: fixture.session, token: "secret", provider: .gitLab)
            do {
                _ = try await client.get(URL(string: "https://gitlab.com/test")!)
                XCTFail("Expected HTTP \(code) to throw")
            } catch { XCTAssertTrue(error.localizedDescription.contains(expected), error.localizedDescription) }
        }
    }

    func testLargeLogIsBounded() async throws {
        let fixture = FixtureSession { _ in (200, [:], Data(repeating: 65, count: 1_048_600)) }
        let client = DiagnosticsClient(session: fixture.session, token: "secret", provider: .gitLab)
        let (data, _, truncated) = try await client.get(URL(string: "https://gitlab.com/log")!, log: true)
        XCTAssertEqual(data.count, 1_048_576)
        XCTAssertTrue(truncated)
        let excerpt = LogExcerpt.extract(data, token: "secret", downloadTruncated: truncated)
        XCTAssertLessThanOrEqual(excerpt.text.count, 16_000)
        XCTAssertTrue(excerpt.isTruncated)
    }

    func testExcerptCleansANSIAndIncludesErrorContext() {
        let data = Data("setup\n\u{001B}[31mERROR: broken\u{001B}[0m\nafter\nBearer abc123\nglpat-abc123".utf8)
        let excerpt = LogExcerpt.extract(data, token: "")
        XCTAssertTrue(excerpt.matchedError)
        XCTAssertTrue(excerpt.text.contains("setup"))
        XCTAssertTrue(excerpt.text.contains("after"))
        XCTAssertFalse(excerpt.text.contains("\u{001B}"))
        XCTAssertFalse(excerpt.text.contains("abc123"))
    }

    func testNoErrorUsesTailAndPreservesLineNumbers() {
        let text = (1...100).map { "line \($0)" }.joined(separator: "\n")
        let excerpt = LogExcerpt.extract(Data(text.utf8), token: "")
        XCTAssertFalse(excerpt.matchedError)
        XCTAssertTrue(excerpt.text.hasPrefix("61  line 61"))
        XCTAssertTrue(excerpt.text.contains("100  line 100"))
        XCTAssertTrue(excerpt.isTruncated)
    }

    func testSignedDownloadRedirectStripsCredentials() {
        var request = URLRequest(url: URL(string: "https://signed.example.com/log")!)
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        request.setValue("secret", forHTTPHeaderField: "PRIVATE-TOKEN")
        let redirected = DiagnosticsRedirectDelegate.safeRedirect(from: URL(string: "https://api.github.com"), to: request)
        XCTAssertNil(redirected?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(redirected?.value(forHTTPHeaderField: "PRIVATE-TOKEN"))
        request.url = URL(string: "http://signed.example.com/log")!
        XCTAssertNil(DiagnosticsRedirectDelegate.safeRedirect(from: URL(string: "https://api.github.com"), to: request))
    }

    func testEmptyJobsAndMissingLog() async throws {
        let fixture = FixtureSession { request in
            if request.url!.path.hasSuffix("/trace") { return (200, [:], Data()) }
            return (200, ["X-Next-Page": ""], Data("[]".utf8))
        }
        let provider = GitLabCIProvider(accessToken: "token", repositoryNames: [], session: fixture.session)
        let result = try await provider.failedJobs(repository: repository(), pipeline: pipeline())
        XCTAssertTrue(result.jobs.isEmpty)
        let job = FailedJob(id: 1, name: "Test", summary: "", webURL: repository().url)
        do {
            _ = try await provider.jobLog(repository: repository(), job: job)
            XCTFail("Expected an explicit unavailable log state")
        } catch { XCTAssertTrue(error.localizedDescription.contains("No log")) }
    }
}

private actor DelayedDiagnostics: PipelineDiagnosticsProviding {
    private var firstLog: CheckedContinuation<LogExcerpt, Never>?
    func failedJobs(repository: Repository, pipeline: Pipeline) async throws -> FailedJobs {
        FailedJobs(jobs: [1, 2].map { FailedJob(id: $0, name: "Job \($0)", summary: "Test failed", webURL: repository.url) }, isTruncated: false)
    }
    func jobLog(repository: Repository, job: FailedJob) async throws -> LogExcerpt {
        if job.id == 1 { return await withCheckedContinuation { firstLog = $0 } }
        return LogExcerpt(text: "second", matchedError: true, isTruncated: false)
    }
    var hasPendingLog: Bool { firstLog != nil }
    func finishFirstLog() { firstLog?.resume(returning: LogExcerpt(text: "first", matchedError: true, isTruncated: false)); firstLog = nil }
}

private struct FreshIDsProvider: PipelineProvider {
    let provider = CIProvider.gitLab
    let sourceTitle = "Test"
    func fetchProjects() async throws -> [Project] {
        [Project(id: UUID(), repository: repository(), pipelines: [pipeline()])]
    }
}

@MainActor
final class FailureDetailsModelTests: XCTestCase {
    func testCanceledLogDoesNotPublishResultOrError() async throws {
        let provider = DelayedDiagnostics()
        let model = FailureDetailsModel()
        await model.loadJobs(provider: provider, repository: repository(), pipeline: pipeline())
        let request = Task { await model.loadLog(provider: provider, repository: repository()) }
        for _ in 0..<100 {
            if await provider.hasPendingLog { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        request.cancel()
        await provider.finishFirstLog()
        await request.value
        XCTAssertNil(model.log)
        XCTAssertNil(model.logError)
        XCTAssertFalse(model.logLoading)
    }

    func testOldLogCannotOverwriteNewSelection() async throws {
        let provider = DelayedDiagnostics()
        let model = FailureDetailsModel()
        await model.loadJobs(provider: provider, repository: repository(), pipeline: pipeline())
        let first = Task { await model.loadLog(provider: provider, repository: repository()) }
        for _ in 0..<100 {
            if await provider.hasPendingLog { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let pending = await provider.hasPendingLog
        XCTAssertTrue(pending)
        model.selectedJobID = 2
        await model.loadLog(provider: provider, repository: repository())
        await provider.finishFirstLog()
        await first.value
        XCTAssertEqual(model.log?.text, "second")
        XCTAssertFalse(model.logLoading)
    }

    func testMissingProviderExplainsDemoLimitation() async {
        let model = FailureDetailsModel()
        await model.loadJobs(provider: nil, repository: repository(), pipeline: pipeline())
        XCTAssertTrue(model.jobsError?.contains("Demo") == true)
        XCTAssertFalse(model.jobsLoading)
    }

    func testProjectSelectionSurvivesAutomaticRefreshWithNewUUIDs() async throws {
        let suite = "PipePulseTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "notificationsEnabled")
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(provider: FreshIDsProvider(), defaults: defaults)
        await state.refresh()
        state.selectedProjectID = try XCTUnwrap(state.projects.first?.id)
        let selectedID = state.selectedProjectID
        await state.refresh()
        XCTAssertEqual(state.selectedProject?.id, selectedID)
    }
}
