import XCTest
@testable import PipePulse

final class PipelineModelsTests: XCTestCase {
    func testPipelineDurationFormatting() {
        let pipeline = Pipeline(
            id: UUID(),
            name: "Tests",
            branch: "main",
            status: .success,
            startedAt: .now,
            duration: 142,
            webURL: URL(string: "https://example.com")!
        )

        XCTAssertEqual(pipeline.durationText, "2m 22s")
    }

    func testProjectUsesMostRecentPipeline() {
        let repository = Repository(id: UUID(), owner: "acme", name: "demo", provider: .githubActions, url: URL(string: "https://example.com")!)
        let older = Pipeline(id: UUID(), name: "Build", branch: "main", status: .failed, startedAt: .now.addingTimeInterval(-60), duration: 10, webURL: repository.url)
        let newer = Pipeline(id: UUID(), name: "Build", branch: "main", status: .success, startedAt: .now, duration: 10, webURL: repository.url)
        let project = Project(id: repository.id, repository: repository, pipelines: [older, newer])

        XCTAssertEqual(project.latestPipeline?.id, newer.id)
        XCTAssertEqual(project.name, "demo")
    }

    func testProjectLatestPipelineUsesCreationDate() {
        let repository = Repository(id: UUID(), owner: "acme", name: "demo", provider: .gitLab, url: URL(string: "https://example.com")!)
        let newest = Pipeline(
            id: UUID(), name: "new", branch: "main", status: .success,
            startedAt: .now.addingTimeInterval(-120), duration: 10,
            webURL: repository.url.appending(path: "new"),
            createdAt: .now
        )
        let older = Pipeline(
            id: UUID(), name: "old", branch: "main", status: .failed,
            startedAt: .now, duration: 10,
            webURL: repository.url.appending(path: "old"),
            createdAt: .now.addingTimeInterval(-60)
        )
        let project = Project(id: repository.id, repository: repository, pipelines: [older, newest])

        XCTAssertEqual(project.latestPipeline?.id, newest.id)
    }
}

final class MockPipelineProviderTests: XCTestCase {
    func testMockProviderReturnsProjectsFromMultipleProviders() async throws {
        let projects = try await MockPipelineProvider().fetchProjects()

        XCTAssertEqual(projects.count, 3)
        XCTAssertTrue(projects.contains { $0.repository.provider == .githubActions })
        XCTAssertTrue(projects.contains { $0.repository.provider == .gitLab })
        XCTAssertTrue(projects.allSatisfy { !$0.pipelines.isEmpty })
    }
}

final class GitHubActionsProviderTests: XCTestCase {
    func testGitHubWorkflowStatusMapping() {
        XCTAssertEqual(PipelineStatus(githubStatus: "completed", conclusion: "success"), .success)
        XCTAssertEqual(PipelineStatus(githubStatus: "completed", conclusion: "failure"), .failed)
        XCTAssertEqual(PipelineStatus(githubStatus: "in_progress", conclusion: nil), .running)
        XCTAssertEqual(PipelineStatus(githubStatus: "queued", conclusion: nil), .pending)
        XCTAssertEqual(PipelineStatus(githubStatus: "completed", conclusion: "cancelled"), .canceled)
    }
}

final class GitLabCIProviderTests: XCTestCase {
    func testGitLabPipelineStatusMapping() {
        XCTAssertEqual(PipelineStatus(gitLabStatus: "success"), .success)
        XCTAssertEqual(PipelineStatus(gitLabStatus: "failed"), .failed)
        XCTAssertEqual(PipelineStatus(gitLabStatus: "running"), .running)
        XCTAssertEqual(PipelineStatus(gitLabStatus: "pending"), .pending)
        XCTAssertEqual(PipelineStatus(gitLabStatus: "canceled"), .canceled)
    }
}

@MainActor
final class AppStateTests: XCTestCase {
    func testRefreshCalculatesDashboardCounts() async {
        let suiteName = "PipePulseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let state = AppState(defaults: defaults)

        await state.refresh()

        XCTAssertEqual(state.projects.count, 3)
        XCTAssertEqual(state.successCount, 3)
        XCTAssertEqual(state.failedCount, 2)
        XCTAssertEqual(state.runningCount, 2)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
