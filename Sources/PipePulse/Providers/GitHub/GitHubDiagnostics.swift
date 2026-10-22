import Foundation

extension GitHubActionsProvider: PipelineDiagnosticsProviding {
    private var diagnostics: DiagnosticsClient { DiagnosticsClient(session: session, token: accessToken, provider: provider) }

    private func diagnosticsURL(repository: Repository, suffix: String) throws -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
        guard let owner = repository.owner.addingPercentEncoding(withAllowedCharacters: allowed),
              let name = repository.name.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "https://api.github.com/repos/\(owner)/\(name)/actions/\(suffix)") else {
            throw PipelineProviderError.invalidResponse
        }
        return url
    }

    func failedJobs(repository: Repository, pipeline: Pipeline) async throws -> FailedJobs {
        guard let runID = pipeline.remoteSequence else {
            throw DiagnosticsError.message("Details are unavailable for this run. Open it in GitHub.")
        }
        var jobs: [FailedJob] = []
        for page in 1...5 {
            let url = try diagnosticsURL(repository: repository, suffix: "runs/\(runID)/jobs?filter=latest&per_page=100&page=\(page)")
            let (data, _, _) = try await diagnostics.get(url)
            let response = try JSONDecoder().decode(GitHubJobsResponse.self, from: data)
            jobs += response.jobs.filter { Self.isFailed($0.conclusion) }.map { job in
                let failedSteps = (job.steps ?? []).filter { Self.isFailed($0.conclusion) }.map(\.name)
                return FailedJob(id: job.id, name: job.name,
                                 summary: failedSteps.isEmpty ? "Conclusion: \(job.conclusion ?? "failure")" : "Failed steps: " + failedSteps.joined(separator: ", "),
                                 webURL: job.html_url)
            }
            if response.jobs.isEmpty || page * 100 >= response.total_count {
                return FailedJobs(jobs: jobs, isTruncated: false)
            }
        }
        return FailedJobs(jobs: jobs, isTruncated: true)
    }

    func jobLog(repository: Repository, job: FailedJob) async throws -> LogExcerpt {
        let url = try diagnosticsURL(repository: repository, suffix: "jobs/\(job.id)/logs")
        let (data, _, truncated) = try await diagnostics.get(url, log: true)
        guard !data.isEmpty else { throw DiagnosticsError.message("No log is available for this job yet.") }
        return LogExcerpt.extract(data, token: accessToken, downloadTruncated: truncated)
    }

    private static func isFailed(_ conclusion: String?) -> Bool {
        ["failure", "timed_out", "action_required", "startup_failure", "stale"].contains(conclusion ?? "")
    }
}

private struct GitHubJobsResponse: Decodable {
    let total_count: Int
    let jobs: [Job]
    struct Job: Decodable {
        let id: Int64
        let name: String
        let conclusion: String?
        let html_url: URL
        let steps: [Step]?
    }
    struct Step: Decodable {
        let name: String
        let conclusion: String?
    }
}
