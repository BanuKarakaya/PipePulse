import Foundation
import Combine

@MainActor
final class FailureDetailsModel: ObservableObject {
    @Published private(set) var jobs: [FailedJob] = []
    @Published private(set) var jobsLoading = false
    @Published private(set) var jobsError: String?
    @Published private(set) var jobsTruncated = false
    @Published var selectedJobID: Int64?
    @Published private(set) var log: LogExcerpt?
    @Published private(set) var logLoading = false
    @Published private(set) var logError: String?
    private var jobsRequest = UUID()
    private var logRequest = UUID()

    var selectedJob: FailedJob? { jobs.first { $0.id == selectedJobID } }

    func loadJobs(provider: (any PipelineDiagnosticsProviding)?, repository: Repository, pipeline: Pipeline) async {
        let request = UUID()
        jobsRequest = request
        jobsLoading = true
        jobsError = nil
        defer { if jobsRequest == request { jobsLoading = false } }
        guard let provider else {
            jobsError = "Failure details require a configured GitHub or GitLab integration. Demo runs do not have real logs."
            return
        }
        do {
            let result = try await provider.failedJobs(repository: repository, pipeline: pipeline)
            try Task.checkCancellation()
            guard jobsRequest == request else { return }
            jobs = result.jobs
            jobsTruncated = result.isTruncated
            selectedJobID = jobs.first?.id
        } catch {
            guard !Task.isCancelled, jobsRequest == request else { return }
            jobsError = error.localizedDescription
        }
    }

    func loadLog(provider: (any PipelineDiagnosticsProviding)?, repository: Repository) async {
        let request = UUID()
        logRequest = request
        log = nil
        logError = nil
        logLoading = false
        guard let provider, let job = selectedJob else { return }
        logLoading = true
        defer { if logRequest == request { logLoading = false } }
        do {
            let result = try await provider.jobLog(repository: repository, job: job)
            try Task.checkCancellation()
            guard logRequest == request, selectedJobID == job.id else { return }
            log = result
        } catch {
            guard !Task.isCancelled, logRequest == request, selectedJobID == job.id else { return }
            logError = error.localizedDescription
        }
    }
}
