import AppKit
import SwiftUI
import XCTest
@testable import PipePulse

private struct PreviewDiagnostics: PipelineDiagnosticsProviding {
    let permissionDenied: Bool
    func failedJobs(repository: Repository, pipeline: Pipeline) async throws -> FailedJobs {
        FailedJobs(jobs: [FailedJob(id: 1, name: "unit-tests", summary: "Stage: test · script failure", webURL: repository.url)], isTruncated: false)
    }
    func jobLog(repository: Repository, job: FailedJob) async throws -> LogExcerpt {
        if permissionDenied {
            throw DiagnosticsError.message("Access denied. GitLab needs Pipeline: Read for jobs and Job: Read for logs on this project.")
        }
        return LogExcerpt(text: "34  Running tests…\n35  ERROR: Expected 200, received 500\n36  Test Suite failed\n37  Process exited with code 1", matchedError: true, isTruncated: false)
    }
}

/// Opt-in local rendering, without API calls or modifying the running app.
/// Set PIPEPULSE_PREVIEW_DIRECTORY to an existing temporary directory.
@MainActor
final class FailureDetailsPreviewTests: XCTestCase {
    func testFailureScreenAtMenuBarSize() async throws {
        guard let directory = ProcessInfo.processInfo.environment["PIPEPULSE_PREVIEW_DIRECTORY"] else {
            throw XCTSkip("Set PIPEPULSE_PREVIEW_DIRECTORY to render UI previews.")
        }
        _ = NSApplication.shared
        let repository = Repository(id: UUID(), owner: "demo", name: "pipepulse-test", provider: .gitLab,
                                    url: URL(string: "https://example.com/demo")!)
        let pipeline = Pipeline(id: UUID(), name: "GitLab pipeline #42", branch: "main", status: .failed,
                                startedAt: .now, duration: 12, webURL: repository.url, remoteSequence: 42)
        for denied in [false, true] {
            let view = FailureDetailsView(repository: repository, pipeline: pipeline,
                                          provider: PreviewDiagnostics(permissionDenied: denied), onBack: {})
                .frame(width: 420, height: 570)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, .light)
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: 420, height: 570),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(500))
            hosting.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: directory).appendingPathComponent(denied ? "permission.png" : "failure.png")
            try data.write(to: url)
            XCTAssertGreaterThan(data.count, 1000)
            window.close()
        }
    }
}
