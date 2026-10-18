import AppKit
import XCTest
@testable import PipePulse

private actor ChangingPipelineProvider: PipelineProvider {
    nonisolated let provider = CIProvider.gitLab
    nonisolated let sourceTitle = "GitLab test"
    private let statuses: [PipelineStatus]
    private var index = 0
    private let repository = Repository(id: UUID(), owner: "test", name: "pipeline", provider: .gitLab, url: URL(string: "https://example.com/test/pipeline")!)
    private let pipelineID = UUID()

    init(_ statuses: [PipelineStatus]) { self.statuses = statuses }

    func fetchProjects() async throws -> [Project] {
        let status = statuses[min(index, statuses.count - 1)]
        index += 1
        return [Project(id: repository.id, repository: repository, pipelines: [
            Pipeline(id: pipelineID, name: "Build", branch: "main", status: status,
                     startedAt: .now, duration: nil, webURL: repository.url, remoteSequence: 1)
        ])]
    }
}

@MainActor
final class RefreshRegressionTests: XCTestCase {
    func testRepeatedRefreshThroughRunningSuccessAndFailureWithNativeAnimation() async throws {
        _ = NSApplication.shared
        let suite = "PipePulseTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "notificationsEnabled")
        defer { defaults.removePersistentDomain(forName: suite) }
        let statuses: [PipelineStatus] = [.running, .success, .success, .failed, .running, .success]
        let state = AppState(provider: ChangingPipelineProvider(statuses), defaults: defaults)
        let controller = MenuBarController(appState: state)
        defer { controller.shutdown() }

        for status in statuses {
            await state.refresh()
            XCTAssertFalse(state.isLoading)
            XCTAssertEqual(state.projects.first?.latestPipeline?.status, status)
            XCTAssertEqual(controller.activity, status == .running ? .running : (state.isSuccessPulseActive ? .success : .idle))
            // Let the actual AppKit animation timer render multiple frames.
            try await Task.sleep(for: .milliseconds(250))
        }
        state.returnToDashboard()
        XCTAssertEqual(controller.activity, .idle)
        await state.refresh()
        XCTAssertFalse(state.isLoading)
        XCTAssertEqual(controller.activity, .idle)
    }

    func testActivePipelineAutomaticallyRefreshesToSuccess() async throws {
        let suite = "PipePulseTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(RefreshInterval.fiveMinutes.rawValue, forKey: "refreshInterval")
        defaults.set(false, forKey: "notificationsEnabled")
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(provider: ChangingPipelineProvider([.running, .success]), defaults: defaults)
        defer { state.stopMonitoring() }
        state.startMonitoring()
        try await Task.sleep(for: .seconds(6))
        XCTAssertEqual(state.projects.first?.latestPipeline?.status, .success)
        XCTAssertTrue(state.isSuccessPulseActive)
        XCTAssertFalse(state.isLoading)
    }

    func testActivePipelineTakesPriorityOverUnacknowledgedSuccess() {
        let repository = Repository(id: UUID(), owner: "test", name: "repo", provider: .gitLab, url: URL(string: "https://example.com")!)
        for status in [PipelineStatus.running, .pending] {
            let pipeline = Pipeline(id: UUID(), name: "Build", branch: "main", status: status, startedAt: .now, duration: nil, webURL: repository.url)
            XCTAssertEqual(MenuBarActivity.resolve(projects: [Project(id: repository.id, repository: repository, pipelines: [pipeline])], successPulse: true), .running)
        }
    }
}
