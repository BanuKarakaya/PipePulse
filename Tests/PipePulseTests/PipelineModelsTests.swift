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

@MainActor
final class AppStateTests: XCTestCase {
    func testRefreshCalculatesDashboardCounts() async {
        let suiteName = "PipePulseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let state = AppState(defaults: defaults)

        await state.refresh()

        XCTAssertEqual(state.projects.count, 3)
        XCTAssertEqual(state.successCount, 1)
        XCTAssertEqual(state.failedCount, 1)
        XCTAssertEqual(state.runningCount, 1)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
